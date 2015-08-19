module OpenBEL
  module Transform

    class AnnotationTransform

      SERVER_PATTERN = %r{/api/annotations/([^/]*)/values/([^/]*)/?}
      RDFURI_PATTERN = %r{/bel/namespace/([^/]*)/([^/]*)/?}
      URI_PATTERNS = [
        %r{/api/annotations/([^/]*)/values/([^/]*)/?},
        %r{/bel/namespace/([^/]*)/([^/]*)/?}
      ]
      ANNOTATION_VALUE_URI = "%s/api/annotations/%s/values/%s"

      def initialize(annotation_api)
        @annotation_api = annotation_api
      end

      def transform_evidence!(evidence, base_url)
        if evidence
          experiment_context = evidence.experiment_context
          if experiment_context != nil
            experiment_context.values.map! { |annotation|
              transform_annotation(annotation, base_url)
            }
          end
        end
      end

      def transform_annotation(annotation, base_url)
        if annotation[:uri]
          transformed = transform_uri(annotation[:uri], base_url)
          return transformed if transformed != nil
        end

        if annotation[:name] && annotation[:value]
          name  = annotation[:name]
          value = annotation[:value]
          transform_name_value(name, value, base_url)
        elsif annotation.respond_to?(:each)
          name  = annotation[0]
          value = annotation[1]
          transform_name_value(name, value, base_url)
        end
      end

      private

      def transform_uri(uri, base_url)
        URI_PATTERNS.map { |pattern|
          match = pattern.match(uri)
          match ? transform_name_value(match[1], match[2], base_url) : nil
        }.compact.first
      end

      def transform_name_value(name, value, base_url)
        structured_annotation(name, value, base_url) || free_annotation(name, value)
      end

      def structured_annotation(name, value, base_url)
        annotation = @annotation_api.find_annotation(name)
        if annotation
          annotation_label = annotation.prefLabel
          if value.respond_to?(:each)
            {
              :name  => annotation_label,
              :value => value.map { |v|
                mapped = @annotation_api.find_annotation_value(annotation, v)
                mapped ? mapped.prefLabel : v
              }
            }
          else
            annotation_value = @annotation_api.find_annotation_value(annotation, value)
            if annotation_value
              value_label = annotation_value.prefLabel
              {
                :name  => annotation.prefLabel,
                :value => annotation_value.prefLabel,
                :uri   => ANNOTATION_VALUE_URI % [base_url, annotation_label, value_label]
              }
            else
              {
                :name  => annotation.prefLabel,
                :value => value
              }
            end
          end
        end
      end

      def free_annotation(name, value)
        {
          :name  => normalize_annotation_name(name),
          :value => value
        }
      end

      def normalize_annotation_name(name, options = {})
        name_s = name.to_s

        if name_s.empty?
          nil
        else
          name_s.
            split(%r{[^a-zA-Z0-9]+}).
            map! { |word| word.capitalize }.
            join
        end
      end
    end

  end
end
