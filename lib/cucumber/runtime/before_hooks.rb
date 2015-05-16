module Cucumber
  class Runtime
    class BeforeHooks
      def initialize(hooks_data)
        @hooks_data = hooks_data
      end

      def apply_to(test_case)
        test_case.with_steps(
          before_hooks(test_case.source) + test_case.test_steps
        )
      end

      private

      def before_hooks(source)
        @hooks_data.map do |hook_data|
          Hooks.before_hook(source, hook_data[:location], &hook_data[:action_block])
        end
      end
    end
  end
end
