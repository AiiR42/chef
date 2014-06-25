#
# Author:: Adam Jacob (<adam@opscode.com>)
# Copyright:: Copyright (c) 2008 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/config'
require 'uri'
require 'chef/rest'
require 'chef/node'
require 'chef/role'
require 'chef/data_bag'
require 'chef/data_bag_item'

class Chef
  class Search
    class Query

      attr_accessor :rest

      def initialize(url=nil)
        @rest = Chef::REST.new(url ||Chef::Config[:chef_server_url])
      end

      # new search api that allows for a cleaner implementation of things like return filters
      # (formerly known as 'partial search'). A passthrough to either the old style ("full search")
      # or the new 'filtered' search
      def search_new(type, query="*:*", args=nil, &block)
        raise ArgumentError, "Type must be a string or a symbol!" unless (type.kind_of?(String) || type.kind_of?(Symbol))

        # if args is nil, we need to set some defaults, for backwards compatibility
        if args.nil?
          args = Hash.new
          args[:sort] = 'X_CHEF_id_CHEF_X asc'
          args[:start] = 0
          args[:rows] = 1000
        end

        query_string = create_query_string(type, query, args)
        response = call_rest_service(query_string, args)
        if block
          response["rows"].each { |o| block.call(o) unless o.nil?}
          unless (response["start"] + response["rows"].length) >= response["total"]
            args[:start] = response["start"] + args[:rows]
            search_new(type, query, args, &block)
          end
          true
        else
          [ response["rows"], response["start"], response["total"] ]
        end

      end

      def search(type, query='*:*', *args, &block)
        raise ArgumentError, "Type must be a string or a symbol!" unless (type.kind_of?(String) || type.kind_of?(Symbol))
        raise ArgumentError, "Invalid number of arguments!" if (args.size > 3)
        if args.size == 1 && args[0].is_a?(Hash)
          args_hash = args[0]
          search_new(type, query, args_hash, &block)
        else
          sort = args.length >= 1 ? args[0] : 'X_CHEF_id_CHEF_X asc'
          start = args.length >= 2 ? args[1] : 0
          rows = args.length >= 3 ? args[2] : 1000
          search_old(type, query, sort, start, rows, &block)
        end
      end


      # Search Solr for objects of a given type, for a given query. If you give
      # it a block, it will handle the paging for you dynamically.
      def search_old(type, query="*:*", sort='X_CHEF_id_CHEF_X asc', start=0, rows=1000, &block)
        raise ArgumentError, "Type must be a string or a symbol!" unless (type.kind_of?(String) || type.kind_of?(Symbol))

        # argify things
        args = Hash.new
        args[:sort] = sort
        args[:start] = start
        args[:rows] = rows

        search_new(type, query, args, &block)
      end

      def list_indexes
        @rest.get_rest("search")
      end

      private
        def escape(s)
          s && URI.escape(s.to_s)
        end
        
        # create the full rest url string
        def create_query_string(type, query, args)
          # create some default variables just so we don't break backwards compatibility
          sort = args.key?(:sort) ? args[:sort] : 'X_CHEF_id_CHEF_X asc'
          start = args.key?(:start) ? args[:start] : 0
          rows = args.key?(:rows) ? args[:rows] : 1000

          return "search/#{type}?q=#{escape(query)}&sort=#{escape(sort)}&start=#{escape(start)}&rows=#{escape(rows)}"
        end

        def call_rest_service(query_string, args)
          if args.key?(:filter_result)
            response = @rest.post_rest(query_string, args[:filter_result])
            response_rows = response['rows'].map { |row| row['data'] }
          else
            response = @rest.get_rest(query_string)
            response_rows = response['rows']
          end
          return response
        end
    end
  end
end
