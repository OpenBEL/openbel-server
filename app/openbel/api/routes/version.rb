require_relative '../version'
require 'rack/mime'

module OpenBEL
  module Routes

    class Version < Base

      JSON             = Rack::Mime.mime_type('.json')
      TEXT             = Rack::Mime.mime_type('.txt')
      ACCEPTED_TYPES   = {'json' => JSON, 'text' => TEXT}
      DEFAULT_TYPE     = TEXT

      options '/api/version' do
        response.headers['Allow'] = 'OPTIONS,GET'
        status 200
      end

      get '/api/version' do
        accept_type = request.accept.find { |accept_entry|
          ACCEPTED_TYPES.values.include?(accept_entry.to_s)
        }
        accept_type ||= DEFAULT_TYPE

        format = params[:format]
        if format
          accept_type = ACCEPTED_TYPES[format]
          halt 406 unless accept_type
        end

        if accept_type == JSON
          render_json(
            {
              :version => {
                :string                    => OpenBEL::Version.to_s,
                :semantic_version_numbers  => OpenBEL::Version.to_a
              }
            }
          )
        else
          response.headers['Content-Type'] = 'text/plain'
          OpenBEL::Version.to_s
        end
      end
    end
  end
end
# vim: ts=2 sw=2:
# encoding: utf-8
