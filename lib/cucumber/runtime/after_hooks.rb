module Cucumber
  class Runtime
    class AfterHooks
      def initialize(hooks_data)
        @hooks_data = hooks_data
      end

      def apply_to(test_case)
        test_case.with_steps(
          test_case.test_steps + after_hooks(test_case.source).reverse
        )
      end

      private

      def after_hooks(source)
        @hooks_data.map do |hook_data|
          Hooks.after_hook(source, hook_data[:location], &hook_data[:action_block])
        end
      end
    end
  end
end
