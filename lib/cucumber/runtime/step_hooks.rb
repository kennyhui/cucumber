module Cucumber
  class Runtime
    class StepHooks
      def initialize(hooks_data)
        @hooks_data = hooks_data
      end

      def apply(test_steps)
        test_steps.flat_map do |test_step|
          [test_step] + after_step_hooks(test_step)
        end
      end

      private
      def after_step_hooks(test_step)
        @hooks_data.map do |hook_data|
          Hooks.after_step_hook(test_step.source, hook_data[:location], &hook_data[:action_block])
        end
      end
    end
  end
end
