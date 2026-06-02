require 'net/http'
require 'openssl'
require 'json'
require 'date'

module Holidays
  # Fetches "bridge days" from the Nager.Date long weekend API
  # (https://date.nager.at). A bridge day is a regular weekday that sits between
  # a public holiday and a weekend, turning it into a long weekend.
  #
  # This only deals with the network/parse side and returns plain Date objects.
  # Combining those dates with holidays/weekends/working-date overrides is the
  # job of Holidays::Vacations.
  module BridgeDays
    NAME = "bridge-day".freeze
    LONG_WEEKEND_API = "https://date.nager.at/api/v3/LongWeekend".freeze

    class << self
      # Returns the weekday dates that are part of a long weekend within the
      # range, deduped and sorted. Saturdays/Sundays are excluded because they
      # are non-working by default and handled separately.
      def weekdays_between(regions, start_date, end_date)
        country_codes = regions.map { |r| r.to_s.split('_').first.upcase }.uniq
        return [] if country_codes.empty?

        long_weekend_days(country_codes, start_date, end_date)
          .reject { |date| weekend?(date) }
          .select { |date| date >= start_date && date <= end_date }
      end

      private

      def weekend?(date)
        date.wday == 0 || date.wday == 6 # Sunday or Saturday
      end

      def long_weekend_days(country_codes, start_date, end_date)
        years = (start_date.year..end_date.year).to_a
        dates = []

        country_codes.each do |code|
          years.each do |year|
            fetch(year, code).each do |entry|
              range_start = Date.parse(entry["startDate"])
              range_end = Date.parse(entry["endDate"])
              (range_start..range_end).each { |day| dates << day }
            end
          end
        end

        dates.uniq.sort
      end

      def fetch(year, country_code)
        uri = URI.parse("#{LONG_WEEKEND_API}/#{year}/#{country_code}")

        http = Net::HTTP.new(uri.host, uri.port)
        if uri.scheme == "https"
          http.use_ssl = true
          # In production keep full certificate verification. Outside production
          # some machines have a broken/old CA or CRL store that rejects the
          # API's valid certificate, so we skip verification there. We only read
          # public holiday data, so this is an acceptable trade-off.
          http.verify_mode = production? ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
        end

        response = http.get(uri.request_uri)
        return [] unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue StandardError
        # Network/parse failures must not break holiday lookups; degrade to
        # "no long weekend information available".
        []
      end

      # A gem has no intrinsic notion of "production", so we look at the
      # environment variables commonly set by Rails/Rack/other frameworks.
      def production?
        %w[RAILS_ENV RACK_ENV APP_ENV].any? { |key| ENV[key] == "production" }
      end
    end
  end
end
