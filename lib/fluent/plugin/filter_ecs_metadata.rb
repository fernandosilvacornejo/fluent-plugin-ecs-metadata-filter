$LOAD_PATH.unshift File.expand_path('../../../lib', __FILE__)

require 'fluent/plugin/filter'

module Fluent::Plugin
  class ECSMetadataFilter < Filter
    Fluent::Plugin.register_filter('ecs_metadata', self)

    config_param :cache_size,     :integer, default: 1000
    config_param :cache_ttl,      :integer, default: 60 * 60
    config_param :merge_json_log, :bool,    default: true
    config_param :container_id_field, :string,  default: 'container_id_full'
    config_param :fields_key,     :string,  default: 'ecs'
    config_param :fields,         :array,
                 default:          %w(family cluster name container_instance_arn docker_name
                                      docker_id container_instance_version desired_status
                                      known_status name task_arn version task_id),
                 value_type:      :string

    def configure(conf)
      super

      require 'fluent_ecs'

      validate_params

      FluentECS.configure do |c|
        c.cache_size = @cache_size
        c.cache_ttl  = @cache_ttl < 0 ? :none : @cache_ttl
        c.fields     = @fields
      end
    end

    def filter_stream(tag, es)
      new_es   = Fluent::MultiEventStream.new

      es.each do |time, record|
        metadata = get_metadata(record)
        if metadata
          record = merge_log_json(record) if merge_json_logs?
          if @fields_key.empty?
            record.merge! metadata.to_h
          else
            record[@fields_key] = metadata.to_h
          end
        end

        new_es.add(time, record)
      end

      new_es
    end

    def validate_params
      bad_field = @fields.find { |f| !FluentECS::Container.method_defined?(f) }
      raise Fluent::ConfigError, "Invalid field: '#{bad_field}'" if bad_field
    end

    def get_metadata(record)
      container_id = record[@container_id_field]
      FluentECS::Container.find(container_id) unless container_id.nil?
    rescue FluentECS::IntrospectError => e
      log.error(e)
      nil
    end

    def looks_like_json?(str)
      str.is_a?(String) && str[0] == '{' && str[-1] == '}'
    end

    def merge_json_logs?
      @merge_json_log
    end

    def merge_log_json(record)
      log = record['log']
      if looks_like_json?(log)
        begin
          record = JSON.parse(log).merge!(record)
          record.delete('log')
        rescue JSON::ParserError => e
          self.log.error(e)
        end
      end

      record
    end
  end
end
