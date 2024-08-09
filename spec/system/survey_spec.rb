# # frozen_string_literal: true

# Waiting for backport: https://github.com/decidim/decidim/pull/13283
# require "spec_helper"
#
# describe "Answer a survey", type: :system do
#   let(:manifest_name) { "surveys" }
#
#   let(:title) do
#     {
#       "en" => "Survey's title",
#       "ca" => "Títol de l'enquesta'",
#       "es" => "Título de la encuesta"
#     }
#   end
#   let(:description) do
#     {
#       "en" => "<p>Survey's content</p>",
#       "ca" => "<p>Contingut de l'enquesta</p>",
#       "es" => "<p>Contenido de la encuesta</p>"
#     }
#   end
#   let(:user) { create(:user, :confirmed, organization: component.organization) }
#   let!(:questionnaire) { create(:questionnaire, title: title, description: description) }
#   let!(:survey) { create(:survey, component: component, questionnaire: questionnaire) }
#   let!(:question) { create(:questionnaire_question, questionnaire: questionnaire, position: 0) }
#
#   include_context "with a component"
#
#   it_behaves_like "preview component with share_token"
#
#   context "when the survey doesn't allow answers" do
#     it "does not allow answering the survey" do
#       visit_component
#
#       expect(page).to have_i18n_content(questionnaire.title, upcase: true)
#       expect(page).to have_i18n_content(questionnaire.description)
#
#       expect(page).to have_no_i18n_content(question.body)
#
#       expect(page).to have_content("The form is closed and cannot be answered.")
#     end
#   end
#
#   context "when the survey requires permissions to be answered" do
#     before do
#       permissions = {
#         answer: {
#           authorization_handlers: {
#             "dummy_authorization_handler" => { "options" => {} }
#           }
#         }
#       }
#
#       component.update!(permissions: permissions)
#       visit_component
#     end
#
#     it "shows a modal dialog" do
#       expect(page).to have_content("I fill in my phone number")
#     end
#   end
#
#   context "when the survey allow answers" do
#     context "when the survey is closed by start and end dates" do
#       before do
#         component.update!(settings: { starts_at: 1.week.ago, ends_at: 1.day.ago })
#       end
#
#       it "does not allow answering the survey" do
#         visit_component
#
#         expect(page).to have_i18n_content(questionnaire.title, upcase: true)
#         expect(page).to have_i18n_content(questionnaire.description)
#
#         expect(page).to have_no_i18n_content(question.body)
#
#         expect(page).to have_content("The form is closed and cannot be answered.")
#       end
#     end
#
#     context "when the survey is open" do
#       before do
#         component.update!(
#           step_settings: {
#             component.participatory_space.active_step.id => {
#               allow_answers: true
#             }
#           },
#           settings: { starts_at: 1.week.ago, ends_at: 1.day.from_now }
#         )
#       end
#
#       it_behaves_like "has questionnaire"
#     end
#   end
#
#   context "when survey contains images" do
#     let!(:description) do
#       {
#         "en" => "<p>Survey's content</p><img src=\"#{image_url}\" /><iframe src=\"#{image_url}\"></iframe>",
#         "ca" => "<p>Contingut de l'enquesta</p><img src=\"#{image_url}\" /><iframe src=\"#{image_url}\"></iframe>",
#         "es" => "<p>Contenido de la encuesta</p><img src=\"#{image_url}\" /><iframe src=\"#{image_url}\"></iframe>"
#       }
#     end
#     let(:image_url) { "https://decidim.org/assets/decidim/logo-2x-1b6d1f7f7d3f5d7d3f5d7d3f5d7d3f5d7d3f5d7d3f5d7d3f5d7d3f5d7d3f5d.png" }
#     let(:router) { Decidim::EngineRouter.main_proxy(component) }
#
#     it "shows image" do
#       visit_component
#       # click_link "Change cookie settings"
#       # click_button "Accept all"
#       expect(page).to have_selector("img[src='#{image_url}']")
#       # With cookie banner iframe is deactivated
#       expect(page).to have_selector("iframe[src='#{image_url}']")
#     end
#   end
#
#   context "when survey has action log entry" do
#     let!(:action_log) { create(:action_log, user: user, organization: component.organization, resource: survey, component: component, participatory_space: component.participatory_space, visibility: "all") }
#     let(:router) { Decidim::EngineRouter.main_proxy(component) }
#
#     it "shows action log entry" do
#       page.visit decidim.profile_activity_path(nickname: user.nickname)
#       expect(page).to have_content("New survey at #{translated(survey.component.participatory_space.title)}")
#       expect(page).to have_link(translated(survey.questionnaire.title), href: router.survey_path(survey))
#     end
#   end
#
#   def questionnaire_public_path
#     main_component_path(component)
#   end
# end
