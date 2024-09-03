# frozen_string_literal: true

module Decidim
  module Budgets
    # This cell overrides *_path methods from Decidim::TagsCell for project tags
    class ProjectTagsCell < Decidim::TagsCell
      private

      def category_path
        generate_filtered_path("with_any_category", model.category.id.to_s)
      end

      def scope_path
        generate_filtered_path("with_any_scope", model.scope.id.to_s)
      end

      def generate_filtered_path(filter_key, filter_value)
        resource = resource_locator([model.budget, model]).index(filter: { filter_key => [filter_value] })

        if request.path.include?("voting")
          filter = resource.split("?")[1]
          "#{request.path}?#{filter}"
        else
          resource
        end
      end
    end
  end
end
