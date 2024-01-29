# frozen_string_literal: true

require_relative '../ext'
require_relative '../../configuration/settings'

module Datadog
  module Tracing
    module Contrib
      module ActiveJob
        module Configuration
          # Custom settings for the DelayedJob integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :enabled do |o|
              o.type :bool
              o.env Ext::ENV_ENABLED
              o.default true
            end

            option :analytics_enabled do |o|
              o.type :bool
              o.env Ext::ENV_ANALYTICS_ENABLED
              o.default false
            end

            option :analytics_sample_rate do |o|
              o.type :float
              o.env Ext::ENV_ANALYTICS_SAMPLE_RATE
              o.default 1.0
            end
          end
        end
      end
    end
  end
end
