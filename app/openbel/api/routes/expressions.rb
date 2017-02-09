require 'cgi'
require 'bel'
require 'uri'
require 'bel_parser/ast_filter'
require 'bel_parser/ast_generator'
require 'bel_parser/completion'
require 'bel_parser/expression/model'
require 'bel_parser/expression/parser'
require 'bel_parser/expression/validator'
require 'bel_parser/language/expression_validator'
require 'bel_parser/language/semantics'
require 'bel_parser/parsers/serializer'
require 'bel_parser/resources'
require 'bel_parser/resource/jena_tdb_reader'

module OpenBEL
  module Routes

    class Expressions < Base
      include BELParser::Parsers

      def initialize(app)
        super

        # Obtain configured BEL version.
        bel_version   = OpenBEL::Settings[:bel][:version]
        @spec         = BELParser::Language.specification(bel_version)

        # RdfRepository using Jena.
        tdb = OpenBEL::Settings[:resource_rdf][:jena][:tdb_directory]
        @rr = BEL::RdfRepository.plugins[:jena].create_repository(:tdb_directory => tdb)

        # Annotations using RdfRepository
        @annotations = BEL::Resource::Annotations.new(@rr)
        # Namespaces using RdfRepository
        @namespaces  = BEL::Resource::Namespaces.new(@rr)

        @supported_namespaces = Hash[
          @namespaces.each.map { |ns|
            prefix = ns.prefix.first.upcase

            [
              prefix,
              BELParser::Expression::Model::Namespace.new(
                prefix,
                ns.uri
              )
            ]
          }
        ]

        # Resource Search using SQLite.
        @search = BEL::Resource::Search.plugins[:sqlite].create_search(
          :database_file => OpenBEL::Settings[:resource_search][:sqlite][:database_file]
        )

        @expression_validator = BELParser::Expression::Validator.new(
          @spec,
          @supported_namespaces,
          BELParser::Resource::JenaTDBReader.new(tdb),
          BELParser::Resource.default_url_reader)
      end

      configure :development do |config|
        Expressions.reset!
        use Rack::Reloader
      end

      options '/api/expressions/*/completions' do
        response.headers['Allow'] = 'OPTIONS,GET'
        status 200
      end

      options '/api/expressions/*/components/?' do
        response.headers['Allow'] = 'OPTIONS,GET'
        status 200
      end

      options '/api/expressions/*/components/terms?' do
        response.headers['Allow'] = 'OPTIONS,GET'
        status 200
      end

      options '/api/expressions/*/validation-result/?' do
        response.headers['Allow'] = 'OPTIONS,GET'
        status 200
      end

      helpers do

        def normalize_relationship(relationship)
          return nil unless relationship
          BEL::Language::RELATIONSHIPS[relationship.to_sym]
        end

        def statement_components(bel_statement, flatten = false)
          obj = {}
          if flatten
            obj.merge!({
              :subject      => bel_statement.subject ? bel_statement.subject.to_s : nil,
              :relationship => bel_statement.relationship && bel_statement.relationship.long,
              :object       => bel_statement.object ? bel_statement.object.to_s : nil
            })
          else
            obj.merge!({
              :subject      => term_components(bel_statement.subject),
              :relationship => bel_statement.relationship && bel_statement.relationship.to_h,
              :object       => term_components(bel_statement.object)
            })
          end

          obj
        end

        def arg_components(bel_argument)
          case bel_argument
          when BELParser::Expression::Model::Parameter
            parameter_components(bel_argument)
          when BELParser::Expression::Model::Term
            term_components(bel_argument)
          else
            nil
          end
        end

        def term_components(bel_term)
          return nil unless bel_term

          {
            :term => {
              :function  => bel_term.function.to_h,
              :arguments => bel_term.arguments.map { |a| arg_components(a) }
            }
          }
        end

        def parameter_components(bel_parameter)
          return nil unless bel_parameter
          namespace = bel_parameter.namespace && bel_parameter.namespace.to_s

          {
            :parameter => {
              :namespace => namespace,
              :value     => bel_parameter.value.to_s
            }
          }
        end

        def syntax_results(results)
          results.select do |res|
            res.is_a? BELParser::Language::Syntax::SyntaxResult
          end
        end

        def semantics_results(results)
          results.select do |res|
            res.is_a? BELParser::Language::Semantics::SemanticsResult
          end
        end

        def successfully_matched_signatures(results)
          results.select do |res|
            res.is_a?(BELParser::Language::Semantics::SignatureMappingSuccess)
          end
        end

        def signature_warnings(results)
          results.select do |res|
            res.is_a?(BELParser::Language::Semantics::SignatureMappingWarning)
          end
        end
      end

      get '/api/expressions/*/completions/?' do
        bel = params[:splat].first
        caret_position = (params[:caret_position] || bel.length).to_i
        halt 400 unless bel and caret_position

        begin
          completions = BELParser::Completion.complete(bel, @spec, @search, @supported_namespaces, caret_position)
        rescue IndexError => ex
          halt(
            400,
            { 'Content-Type' => 'application/json' },
            render_json({ :status => 400, :msg => ex.to_s })
          )
        end
        halt 404 if completions.empty?

        render_collection(
          completions,
          :completion,
          :bel => bel,
          :caret_position => caret_position
        )
      end

      get '/api/expressions/*/components/?' do
        bel     = params[:splat].first
        flatten = as_bool(params[:flatten])

        begin
          statement =
            BELParser::Expression.parse_statements(
              bel,
              @spec,
              @supported_namespaces
          )
          halt 404 unless statement
        rescue Exception => ex
          halt(
              422,
              {'Content-Type' => 'application/json'},
              render_json({ :status => 422, :status_name => 'UNPROCESSABLE ENTITY', :msg => ex.to_s })
          )
        end

        response.headers['Content-Type'] = 'application/json'
        MultiJson.dump({
          :expression_components => statement_components(statement, flatten),
          :statement_short_form  => statement.to_s
        })
      end

      get '/api/expressions/*/components/terms?' do
        bel         = params[:splat].first
        functions   = CGI::parse(env["QUERY_STRING"])['function']
        flatten     = as_bool(params[:flatten])
        inner_terms = as_bool(params[:inner_terms])

        terms =
          BELParser::Expression.parse_terms(
            bel,
            @spec)
        halt 404 if terms.empty?

        if !functions.empty?
          functions = functions.map(&:to_sym)
          terms =
            terms.select do |term|
              functions.any? { |match| term.function === match }
            end
        end

        if inner_terms
          terms =
            terms.flat_map do |term|
              term.arguments.select do |arg|
                arg.is_a?(BELParser::Expression::Model::Term)
              end
            end
        end

        terms = terms.to_a
        halt 404 if terms.empty?

        response.headers['Content-Type'] = 'application/json'
        if flatten
          MultiJson.dump({
            :terms => terms.map { |term| term.to_s }
          })
        else
          MultiJson.dump({
            :terms => terms.map { |term| term_components(term) }
          })
        end
      end

      # Produce validation result for BEL expression using the current language.
      get '/api/expressions/*/validation/?' do
        bel = params[:splat].first

        filter =
          BELParser::ASTFilter.new(
            BELParser::ASTGenerator.new("#{bel}\n"),
            :simple_statement,
            :observed_term,
            :nested_statement
          )
        _, _, ast = filter.each.first

        if ast.nil? || ast.empty?
          halt(
            400,
            {'Content-Type' => 'application/json'},
            render_json(
              {
                validation: {
                  expression:      bel,
                  valid_syntax:    false,
                  valid_semantics: false,
                  message:         'Invalid syntax.',
                  warnings:        [],
                  term_signatures: []
                }
              }
            )
          )
        end

        message = ''
        terms   = ast.first.traverse.select { |node| node.type == :term }.to_a

        semantics_functions =
          BELParser::Language::Semantics.semantics_functions.reject { |fun|
            fun == BELParser::Language::Semantics::SignatureMapping
          }

        semantic_warnings =
          ast
            .first
            .traverse
            .flat_map { |node|
              semantics_functions.flat_map { |func|
                func.map(node, @spec, @supported_namespaces)
              }
            }
            .compact

        if semantic_warnings.empty?
          valid = true
        else
          valid = false
          message =
            semantic_warnings.reduce('') { |msg, warning|
              msg << "#{warning}\n"
            }
          message << "\n"
        end

        urir      = BELParser::Resource.default_uri_reader
        urlr      = BELParser::Resource.default_url_reader
        validator = BELParser::Language::ExpressionValidator.new(@spec, @supported_namespaces, urir, urlr)
        term_semantics =
          terms.map { |term|
            term_result = validator.validate(term)
            valid      &= term_result.valid_semantics?
            bel_term    = serialize(term)

            unless valid
              message << "Term: #{bel_term}\n"
              term_result.invalid_signature_mappings.map { |m|
                message << "  #{m}\n"
              }
              message << "\n"
            end

            {
              term:               bel_term,
              valid:              term_result.valid_semantics?,
              valid_signatures:   term_result.valid_signature_mappings.map(&:to_s),
              invalid_signatures: term_result.invalid_signature_mappings.map(&:to_s)
            }
          }

        halt(
          valid ? 200 : 422,
          {'Content-Type' => 'application/json'},
          render_json(
            {
              validation: {
                expression:      bel,
                valid_syntax:    true,
                valid_semantics: valid,
                message:         valid ? 'Valid semantics' : message,
                warnings:        semantic_warnings.map(&:to_s),
                term_signatures: term_semantics
              }
            }
          )
        )
      end
    end
  end
end
# vim: ts=2 sw=2:
# encoding: utf-8
