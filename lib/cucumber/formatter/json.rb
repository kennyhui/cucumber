require 'multi_json'
require 'base64'
require 'cucumber/formatter/io'

module Cucumber
  module Formatter
    # The formatter used for <tt>--format json</tt>
    class Json
      include Io

      def initialize(runtime, io, _options)
        @runtime = runtime
        @io = ensure_io(io, 'json')
        @feature_hashes = []
      end

      def before_test_case(test_case)
        builder = Builder.new(test_case)
        unless same_feature_as_previous_test_case?(test_case.feature)
          @feature_hash = builder.feature_hash
          @feature_hashes << @feature_hash
        end
        @test_case_hash = builder.test_case_hash
        if builder.background?
          feature_elements << builder.background_hash
          @element_hash = builder.background_hash
        else
          feature_elements << @test_case_hash
          @element_hash = @test_case_hash
        end
      end

      def before_test_step(test_step)
        return if prepare_world_hook?(test_step)
        if hook?(test_step)
          @step_or_hook_hash = {}
          hooks_of_type(test_step) << @step_or_hook_hash
          return
        end
        if first_step_after_background?(test_step)
          feature_elements << @test_case_hash
          @element_hash = @test_case_hash
        end
        @step_or_hook_hash = create_step_hash(test_step.source.last)
        steps << @step_or_hook_hash
        @step_hash = @step_or_hook_hash
      end

      def after_test_step(test_step, result)
        return if prepare_world_hook?(test_step)
        add_match_and_result(test_step.source.last, result)
      end

      def done
        @io.write(MultiJson.dump(@feature_hashes, pretty: true))
      end

      def puts(message)
        test_step_output << message
      end

      def embed(src, mime_type, _label)
        if File.file?(src)
          content = File.open(src, 'rb') { |f| f.read }
          data = encode64(content)
        else
          if mime_type =~ /;base64$/
            mime_type = mime_type[0..-8]
            data = src
          else
            data = encode64(src)
          end
        end
        test_step_embeddings << { mime_type: mime_type, data: data }
      end

      private

      def same_feature_as_previous_test_case?(feature)
        current_feature[:uri] == feature.file && current_feature[:line] == feature.location.line
      end

      def first_step_after_background?(test_step)
        test_step.source[1].name != @element_hash[:name]
      end

      def prepare_world_hook?(test_step)
        test_step.source.last.location.file.end_with?('cucumber/filters/prepare_world.rb')
      end

      def hook?(test_step)
        hook_source?(test_step.source.last)
      end

      def hook_source?(step_source)
        ['Before hook', 'After hook', 'AfterStep hook'].include? step_source.name
      end

      def current_feature
        @feature_hash ||= {}
      end

      def feature_elements
        @feature_hash[:elements] ||= []
      end

      def steps
        @element_hash[:steps] ||= []
      end

      def hooks_of_type(test_step)
        name = test_step.source.last.name
        if name == 'Before hook'
          return before_hooks
        elsif name == 'After hook'
          return after_hooks
        elsif name == 'AfterStep hook'
          return after_step_hooks
        else
          fail 'Unkown hook type ' + name
        end
      end

      def before_hooks
        @element_hash[:before] ||= []
      end

      def after_hooks
        @element_hash[:after] ||= []
      end

      def after_step_hooks
        @step_hash[:after] ||= []
      end

      def test_step_output
        @step_or_hook_hash[:output] ||= []
      end

      def test_step_embeddings
        @step_or_hook_hash[:embeddings] ||= []
      end

      def create_step_hash(step_source)
        step_hash = {
          keyword: step_source.keyword,
          name: step_source.name,
          line: step_source.location.line
        }
        step_hash[:doc_string] = create_doc_string_hash(step_source.multiline_arg) if step_source.multiline_arg.doc_string?
        step_hash
      end

      def create_doc_string_hash(doc_string)
        {
          value: doc_string.content,
          content_type: doc_string.content_type,
          line: doc_string.location.line
        }
      end

      def add_match_and_result(step_source, result)
        @step_or_hook_hash[:match] = create_match_hash(step_source, result)
        @step_or_hook_hash[:result] = create_result_hash(result)
      end

      def create_match_hash(step_source, result)
        if result.undefined? || hook_source?(step_source)
          location = step_source.location
        else
          location = @runtime.step_match(step_source.name).file_colon_line
        end
        { location: location }
      end

      def create_result_hash(result)
        result_hash = {
          status: result.to_sym
        }
        result_hash[:error_message] = create_error_message(result) if result.failed? || result.pending?
        result.duration.tap { |duration| result_hash[:duration] = duration.nanoseconds }
        result_hash
      end

      def create_error_message(result)
        message_element = result.failed? ? result.exception : result
        message = "#{message_element.message} (#{message_element.class})"
        ([message] + message_element.backtrace).join("\n")
      end

      def encode64(data)
        # strip newlines from the encoded data
        Base64.encode64(data).gsub(/\n/, '')
      end

      class Builder
        attr_reader :feature_hash, :background_hash, :test_case_hash

        def initialize(test_case)
          @background_hash = nil
          test_case.describe_source_to(self)
          test_case.feature.background.describe_to(self)
        end

        def background?
          @background_hash != nil
        end

        def feature(feature)
          @feature_hash = {
            uri: feature.file,
            id: create_id(feature),
            keyword: feature.keyword,
            name: feature.name,
            description: feature.description,
            line: feature.location.line
          }
          @feature_hash[:tags] = create_tags_array(feature.tags) unless feature.tags.empty?
          @test_case_hash[:id].insert(0, @feature_hash[:id] + ';')
        end

        def background(background)
          @background_hash = {
            keyword: background.keyword,
            name: background.name,
            description: background.description,
            line: background.location.line,
            type: 'background'
          }
        end

        def scenario(scenario)
          @test_case_hash = {
            id: create_id(scenario),
            keyword: scenario.keyword,
            name: scenario.name,
            description: scenario.description,
            line: scenario.location.line,
            type: 'scenario'
          }
          @test_case_hash[:tags] = create_tags_array(scenario.tags) unless scenario.tags.empty?
        end

        def scenario_outline(scenario)
          @test_case_hash = {
            id: create_id(scenario) + ';' + @example_id,
            keyword: scenario.keyword,
            name: scenario.name,
            description: scenario.description,
            line: @row.location.line,
            type: 'scenario'
          }
          @test_case_hash[:tags] = create_tags_array(scenario.tags) unless scenario.tags.empty?
        end

        def examples_table(examples_table)
          # the json file have traditionally used the header row as row 1,
          # wheras cucumber-ruby-core used the first example row as row 1.
          @example_id = create_id(examples_table) + ";#{@row.number + 1}"
        end

        def examples_table_row(row)
          @row = row
        end

        private

        def create_id(element)
          element.name.downcase.gsub(/ /, '-')
        end

        def create_tags_array(tags)
          tags_array = []
          tags.each { |tag| tags_array << { name: tag.name, line: tag.location.line } }
          tags_array
        end
      end
    end
  end
end
