require 'bel'
require 'json_schema'
require 'multi_json'
require_relative '../resources/annotation'
require_relative '../resources/completion'
require_relative '../resources/nanopub'
require_relative '../resources/function'
require_relative '../resources/relationship'
require_relative '../resources/match_result'
require_relative '../resources/namespace'
require_relative '../schemas'

module OpenBEL
  module Routes

    class Base < Sinatra::Application
      include OpenBEL::Resource::Annotations
      include OpenBEL::Resource::Nanopub
      include OpenBEL::Resource::Expressions
      include OpenBEL::Resource::Functions
      include OpenBEL::Resource::Relationships
      include OpenBEL::Resource::MatchResults
      include OpenBEL::Resource::Namespaces
      include OpenBEL::Schemas

      DEFAULT_CONTENT_TYPE    = 'application/hal+json'
      DEFAULT_CONTENT_TYPE_ID = :hal
      SPOKEN_CONTENT_TYPES    = %w[application/hal+json application/json]
      SPOKEN_CONTENT_TYPES.concat(
        BEL::Translator.plugins.values.flat_map { |p| p.media_types.map(&:to_s) }
      )
      SCHEMA_BASE_URL         = 'http://next.belframework.org/schemas/'
      RESOURCE_SERIALIZERS    = {
        :annotation                 => AnnotationResourceSerializer,
        :annotation_collection      => AnnotationCollectionSerializer,
        :annotation_value           => AnnotationValueResourceSerializer,
        :completion                 => CompletionResourceSerializer,
        :completion_collection      => CompletionCollectionSerializer,
        :function                   => FunctionResourceSerializer,
        :function_collection        => FunctionCollectionSerializer,
        :relationship               => RelationshipResourceSerializer,
        :relationship_collection    => RelationshipCollectionSerializer,
        :match_result               => MatchResultResourceSerializer,
        :match_result_collection    => MatchResultCollectionSerializer,
        :namespace                  => NamespaceResourceSerializer,
        :namespace_collection       => NamespaceCollectionSerializer,
        :namespace_value            => NamespaceValueResourceSerializer,
        :namespace_value_collection => NamespaceValueCollectionSerializer,
        :nanopub                    => NanopubSerializer,
        :nanopub_resource           => NanopubResourceSerializer,
        :nanopub_collection         => NanopubCollectionSerializer
      }

      disable :protection

      helpers do

        def as_bool(value)
          value == nil ? false : value.to_s =~ (/^(true|t|yes|y|1|on)$/i)
        end

        def wildcard_match(match)
          match.to_s.split(/\W/).map { |v| "*#{v}*"}.join(' ')
        end

        def request_headers
          env.inject({}) { |hdrs, (k,v)|
            hdrs[$1.downcase] = v if k =~ /^http_(.*)/i
            hdrs
          }
        end

        def base_url
          if env['SERVER_PORT'] == 443
            scheme = 'https'
          else
            scheme = 'http'
          end

          "#{scheme}://#{env['HTTP_HOST']}"
        end

        def url
          if env['SERVER_PORT'] == 443
            scheme = 'https'
          else
            scheme = 'http'
          end

          "#{scheme}://#{env['HTTP_HOST']}/#{env['PATH_INFO']}"
        end

        def schema_url(name)
          SCHEMA_BASE_URL + "#{name}.schema.json"
        end

        def wants_default?
          if params[:format]
            return params[:format] == DEFAULT_CONTENT_TYPE
          end

          request.accept.any? { |accept_entry|
            accept_entry.to_s == DEFAULT_CONTENT_TYPE
          }
        end

        def validate_media_type!(content_type, options = {})
          ctype = request.content_type
          valid = ctype.start_with? content_type
          if options[:profile]
            valid &= (%r{profile=#{options[:profile]}} =~ ctype)
          end

          unless valid
            halt(
              415,
              {
                'Content-Type' => 'application/json'
              },
              render_json({
                :status => 415,
                :msg => "Invalid media type #{ctype} (profile: #{options[:profile]})"
              })
            )
          end
        end

        def read_nanopub
          halt 415 unless ::BEL.translator(request.media_type)
          ::BEL.nanopub(request.body, request.media_type, :symbolize_keys => true)
        end

        def read_json
          request.body.rewind
          begin
            MultiJson.load(request.body.read, :symbolize_keys => true)
          rescue MultiJson::ParseError => ex
            halt(
              400,
              {
                'Content-Type' => 'application/json'
              },
              render_json({
                :status => 400,
                :msg => 'Invalid JSON body.',
                :detail => ex.cause.to_s
              })
            )
          end
        end

        def read_filter(filter_json)
          begin
            MultiJson.load filter_json
          rescue MultiJson::ParseError => ex
            halt(
              400,
              {
                'Content-Type' => 'application/json'
              },
              render_json({
                :status => 400,
                :msg => "Invalid JSON filter: #{filter_json}.",
                :detail => ex.cause.to_s
              })
            )
          end
        end

        def write_filter(filter)
          MultiJson.dump(filter)
        end

        def render_json(obj, media_type = 'application/hal+json', profile = nil)
          ctype =
            if profile
              "#{media_type}; profile=#{profile}"
            else
              media_type
            end
          response.headers['Content-Type'] = ctype.to_s
          MultiJson.dump obj
        end

        def validate_schema(data, type)
          self.validate(data, type)
        end

        def render_resource(obj, type, options = {})
          media_type = 'application/hal+json'
          resource_context = {
            :base_url => base_url,
            :url      => url
          }.merge(options)

          type_class = type.to_s.split('_').map(&:capitalize).join
          type_serializer     = self.class.const_get("#{type_class}Serializer")
          resource_serializer = self.class.const_get("#{type_class}ResourceSerializer")

          adapter = Oat::Adapters::HAL
          if options[:adapter]
            adapter = options[:adapter]
          end

          resource = resource_serializer.new(
            type_serializer.new(obj, resource_context, adapter).to_hash,
            resource_context,
            adapter
          ).to_hash

          render_json(resource.to_hash, media_type)
        end

        def render_collection(collection, type, options = {})
          media_type = 'application/hal+json'
          resource_context = {
            :base_url => base_url,
            :url      => url
          }.merge(options)

          type_class = type.to_s.split('_').map(&:capitalize).join
          serializer          = self.class.const_get("#{type_class}Serializer")
          type_serializer     = self.class.const_get("#{type_class}ResourceSerializer")
          resource_serializer = self.class.const_get("#{type_class}CollectionSerializer")

          adapter = Oat::Adapters::HAL
          if options[:adapter]
            adapter = options[:adapter]
          end

          resource = resource_serializer.new(
            collection.map { |obj|
              single = serializer.new(obj, resource_context, adapter).to_hash
              type_serializer.new(single, resource_context, adapter).to_hash
            },
            resource_context,
            adapter
          ).to_hash

          render_json(resource.to_hash, media_type)
        end

        def render(obj, type, options = {})
          media_type = 'application/hal+json'
          resource_context = {
            :base_url => base_url,
            :url      => url
          }.merge(options)

          serializer_class = RESOURCE_SERIALIZERS[type]
          unless serializer_class
            raise NotImplementedError.new("Cannot serialize the #{type} resource.")
          end

          adapter = Oat::Adapters::HAL

          # XXX hack to fix OpenBEL/openbel-server#33
          if options[:as_array]
            render_json(
              {
                type => [serializer_class.new(obj, resource_context, adapter).to_hash]
              },
              media_type
            )
          else
            render_json(
              serializer_class.new(obj, resource_context, adapter).to_hash,
              media_type
            )
          end
        end

        def stream_resource_collection(type, collection, facets, options = {})
          serializer_class = RESOURCE_SERIALIZERS[type]
          unless serializer_class
            raise NotImplementedError.new("Cannot serialize the #{type} resource collection.")
          end

          media_type = resolve_supported_content_type(request)
          resource_context = {
            :base_url => base_url,
            :url      => url
          }.merge(options)

          adapter = Oat::Adapters::HAL

          response.headers['Content-Type'] = media_type
          collection_enum = collection.to_enum

          stream do |response|
            response << %Q({"#{type}": [)
            item = collection_enum.next
            response << render_json(
              serializer_class.new(item, resource_context, adapter).to_hash,
              media_type
            )
            while true
              begin
                item = collection_enum.next
                response << (',' + render_json(
                  serializer_class.new(item, resource_context, adapter).to_hash,
                  media_type
                ))
              rescue StopIteration
                break
              end
            end
            response << ']'

            if facets
              response << ',"facets": ['

              facet_enum = facets.to_enum
              facet_item = facet_enum.next
              filter = MultiJson.load(facet_item['_id'])
              response << MultiJson.dump({
                :category => filter['category'].to_sym,
                :name     => filter['name'].to_sym,
                :value    => filter['value'],
                :filter   => facet_item['_id'],
                :count    => facet_item['count']
              })
              while true
                begin
                  facet_item = facet_enum.next
                  filter = MultiJson.load(facet_item['_id'])
                  response << (',' + MultiJson.dump({
                    :category => filter['category'].to_sym,
                    :name     => filter['name'].to_sym,
                    :value    => filter['value'],
                    :filter   => facet_item['_id'],
                    :count    => facet_item['count']
                  }))
                rescue StopIteration
                  break
                end
              end
              response << ']'
            end

            response << '}'
          end
        end

      end
    end
  end
end
