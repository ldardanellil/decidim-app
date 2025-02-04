# frozen_string_literal: true

require "spec_helper"

module Decidim
  module Proposals
    describe ProposalsController, type: :controller do
      routes { Decidim::Proposals::Engine.routes }

      let(:user) { create(:user, :confirmed, organization: component.organization) }

      let(:proposal_params) do
        {
          component_id: component.id
        }
      end
      let(:params) { { proposal: proposal_params } }

      before do
        request.env["decidim.current_organization"] = component.organization
        request.env["decidim.current_participatory_space"] = component.participatory_space
        request.env["decidim.current_component"] = component
      end

      describe "default_filter_scope_params" do
        let!(:component) { create(:extended_proposal_component) }

        context "when component has no scopes" do
          it "returns all" do
            expect(controller.instance_eval { default_filter_scope_params }).to eq("all")
          end
        end

        context "when component has scope" do
          let(:scope) { create(:scope, organization: component.organization) }

          context "and no subscope" do
            it "returns an array containing all and scope id" do
              component.update!(settings: { scopes_enabled: true, scope_id: scope.id })
              expect(controller.instance_eval { default_filter_scope_params }).to eq(["all", scope.id.to_s])
            end
          end

          context "and subscopes" do
            let!(:subscope_one) { create(:scope, organization: component.organization, parent: scope) }
            let!(:subscope_two) { create(:scope, organization: component.organization, parent: subscope_one) }

            it "returns an array containing all and scope id and subscopes ids" do
              component.update!(settings: { scopes_enabled: true, scope_id: scope.id })
              expect(controller.instance_eval { default_filter_scope_params }).to eq(["all", scope.id.to_s, subscope_one.id.to_s, subscope_two.id.to_s])
            end
          end
        end
      end

      describe "GET index" do
        context "when participatory texts are disabled" do
          let(:component) { create(:extended_proposal_component, :with_geocoding_enabled) }

          it "sorts proposals by search defaults" do
            get :index
            expect(response).to have_http_status(:ok)
            expect(subject).to render_template(:index)
            expect(assigns(:proposals).order_values).to eq(
              [
                Decidim::Proposals::Proposal.arel_table[
                  Decidim::Proposals::Proposal.primary_key
                ] * Arel.sql("RANDOM()")
              ]
            )
            expect(assigns(:proposals).order_values.map(&:to_sql)).to eq(
              ["\"decidim_proposals_proposals\".\"id\" * RANDOM()"]
            )
          end

          it "sets two different collections" do
            geocoded_proposals = create_list :extended_proposal, 10, component: component, latitude: 1.1, longitude: 2.2
            _non_geocoded_proposals = create_list :extended_proposal, 2, component: component, latitude: nil, longitude: nil

            get :index
            expect(response).to have_http_status(:ok)
            expect(subject).to render_template(:index)

            expect(assigns(:proposals).count).to eq 12
            expect(assigns(:all_geocoded_proposals)).to match_array(geocoded_proposals)
          end
        end

        context "when participatory texts are enabled" do
          let(:component) { create(:extended_proposal_component, :with_participatory_texts_enabled) }

          it "sorts proposals by position" do
            get :index
            expect(response).to have_http_status(:ok)
            expect(subject).to render_template(:participatory_text)
            expect(assigns(:proposals).order_values.first.expr.name).to eq("position")
          end

          context "when emendations exist" do
            let!(:amendable) { create(:extended_proposal, component: component) }
            let!(:emendation) { create(:extended_proposal, component: component) }
            let!(:amendment) { create(:amendment, amendable: amendable, emendation: emendation, state: "accepted") }

            it "does not include emendations" do
              get :index
              expect(response).to have_http_status(:ok)
              emendations = assigns(:proposals).select(&:emendation?)
              expect(emendations).to be_empty
            end
          end
        end
      end

      describe "GET new" do
        let(:component) { create(:extended_proposal_component, :with_creation_enabled) }

        before { sign_in user }

        context "when NO draft proposals exist" do
          it "renders the empty form" do
            get :new, params: params
            expect(response).to have_http_status(:ok)
            expect(subject).to render_template(:new)
          end
        end

        context "when draft proposals exist from other users" do
          let!(:others_draft) { create(:extended_proposal, :draft, component: component) }

          it "renders the empty form" do
            get :new, params: params
            expect(response).to have_http_status(:ok)
            expect(subject).to render_template(:new)
          end
        end
      end

      describe "POST create" do
        before { sign_in user }

        context "when creation is not enabled" do
          let(:component) { create(:extended_proposal_component) }

          it "raises an error" do
            post :create, params: params

            expect(flash[:alert]).not_to be_empty
          end
        end

        context "when creation is enabled" do
          let(:component) { create(:extended_proposal_component, :with_creation_enabled) }
          let(:proposal_params) do
            {
              component_id: component.id,
              title: "Lorem ipsum dolor sit amet, consectetur adipiscing elit",
              body: "Ut sed dolor vitae purus volutpat venenatis. Donec sit amet sagittis sapien. Curabitur rhoncus ullamcorper feugiat. Aliquam et magna metus."
            }
          end

          it "creates a proposal" do
            post :create, params: params

            expect(flash[:notice]).not_to be_empty
            expect(response).to have_http_status(:found)
          end

          context "and proposals limit is reached" do
            before do
              allow(controller).to receive(:proposal_limit_reached?).and_return(true)
            end

            it "does not create a proposal and raises an error" do
              post :create, params: params
              expect(response).to have_http_status(:ok)
              expect(flash[:alert]).not_to be_empty
            end
          end
        end
      end

      describe "PATCH update" do
        let(:component) { create(:extended_proposal_component, :with_creation_enabled, :with_attachments_allowed) }
        let(:proposal) { create(:extended_proposal, component: component, users: [user]) }
        let(:proposal_params) do
          {
            title: "Lorem ipsum dolor sit amet, consectetur adipiscing elit",
            body: "Ut sed dolor vitae purus volutpat venenatis. Donec sit amet sagittis sapien. Curabitur rhoncus ullamcorper feugiat. Aliquam et magna metus."
          }
        end
        let(:params) do
          {
            id: proposal.id,
            proposal: proposal_params
          }
        end

        before { sign_in user }

        it "updates the proposal" do
          patch :update, params: params

          expect(flash[:notice]).not_to be_empty
          expect(response).to have_http_status(:found)
        end

        context "when the existing proposal has attachments and there are other errors on the form" do
          include_context "with controller rendering the view" do
            let(:proposal_params) do
              {
                title: "Short",
                # When the proposal has existing photos or documents, their IDs
                # will be sent as Strings in the form payload.
                photos: proposal.photos.map { |a| a.id.to_s },
                documents: proposal.documents.map { |a| a.id.to_s }
              }
            end
            let(:proposal) { create(:extended_proposal, :with_photo, :with_document, component: component, users: [user]) }

            it "displays the editing form with errors" do
              patch :update, params: params

              expect(flash[:alert]).not_to be_empty
              expect(response).to have_http_status(:ok)
              expect(subject).to render_template(:edit)
              expect(response.body).to include("There was a problem saving")
            end
          end
        end
      end

      describe "access links from creating proposal steps" do
        let!(:component) { create(:extended_proposal_component, :with_creation_enabled) }
        let!(:current_user) { create(:user, :confirmed, organization: component.organization) }
        let!(:proposal_extra) { create(:extended_proposal, :draft, component: component, users: [current_user]) }
        let!(:params) do
          {
            id: proposal_extra.id,
            proposal: proposal_params
          }
        end

        before { sign_in user }

        context "when you try to preview a proposal created by another user" do
          it "will not render the preview page" do
            get :preview, params: params
            expect(subject).not_to render_template(:preview)
          end
        end

        context "when you try to complete a proposal created by another user" do
          it "will not render the complete page" do
            get :complete, params: params
            expect(subject).not_to render_template(:complete)
          end
        end

        context "when you try to compare a proposal created by another user" do
          it "will not render the compare page" do
            get :compare, params: params
            expect(subject).not_to render_template(:compare)
          end
        end

        context "when you try to publish a proposal created by another user" do
          it "will not render the publish page" do
            post :publish, params: params
            expect(subject).not_to render_template(:publish)
          end
        end
      end

      describe "withdraw a proposal" do
        let(:component) { create(:extended_proposal_component, :with_creation_enabled) }

        before { sign_in user }

        context "when an authorized user is withdrawing a proposal" do
          let(:proposal) { create(:extended_proposal, component: component, users: [user]) }

          it "withdraws the proposal" do
            put :withdraw, params: params.merge(id: proposal.id)

            expect(flash[:notice]).to include("successfully updated.")
            expect(response).to have_http_status(:found)
            proposal.reload
            expect(proposal.withdrawn?).to be true
          end

          context "and the proposal already has supports" do
            let(:proposal) { create(:extended_proposal, :with_votes, component: component, users: [user]) }

            it "is not able to withdraw the proposal" do
              put :withdraw, params: params.merge(id: proposal.id)

              expect(flash[:alert]).to include("it already has supports.")
              expect(response).to have_http_status(:found)
              proposal.reload
              expect(proposal.withdrawn?).to be false
            end
          end
        end

        describe "when current user is NOT the author of the proposal" do
          let(:current_user) { create(:user, :confirmed, organization: component.organization) }
          let(:proposal) { create(:extended_proposal, component: component, users: [current_user]) }

          context "and the proposal has no supports" do
            it "is not able to withdraw the proposal" do
              expect(WithdrawProposal).not_to receive(:call)

              put :withdraw, params: params.merge(id: proposal.id)

              expect(flash[:alert]).to eq("You are not authorized to perform this action")
              expect(response).to have_http_status(:found)
              proposal.reload
              expect(proposal.withdrawn?).to be false
            end
          end
        end
      end

      describe "GET show" do
        let!(:component) { create(:extended_proposal_component, :with_amendments_enabled) }
        let!(:amendable) { create(:extended_proposal, component: component) }
        let!(:emendation) { create(:extended_proposal, component: component) }
        let!(:amendment) { create(:amendment, amendable: amendable, emendation: emendation) }
        let(:active_step_id) { component.participatory_space.active_step.id }

        context "when the proposal is an amendable" do
          it "shows the proposal" do
            get :show, params: params.merge(id: amendable.id)
            expect(response).to have_http_status(:ok)
            expect(subject).to render_template(:show)
          end

          context "and the user is not logged in" do
            it "shows the proposal" do
              get :show, params: params.merge(id: amendable.id)
              expect(response).to have_http_status(:ok)
              expect(subject).to render_template(:show)
            end
          end
        end

        context "when the proposal is an emendation" do
          context "and amendments VISIBILITY is set to 'participants'" do
            before do
              component.update!(step_settings: { active_step_id => { amendments_visibility: "participants" } })
            end

            context "when the user is not logged in" do
              it "redirects to 404" do
                expect do
                  get :show, params: params.merge(id: emendation.id)
                end.to raise_error(ActionController::RoutingError)
              end
            end

            context "when the user is logged in" do
              before { sign_in user }

              context "and the user is the author of the emendation" do
                let(:user) { amendment.amender }

                it "shows the proposal" do
                  get :show, params: params.merge(id: emendation.id)
                  expect(response).to have_http_status(:ok)
                  expect(subject).to render_template(:show)
                end
              end

              context "and is NOT the author of the emendation" do
                it "redirects to 404" do
                  expect do
                    get :show, params: params.merge(id: emendation.id)
                  end.to raise_error(ActionController::RoutingError)
                end

                context "when the user is an admin" do
                  let(:user) { create(:user, :admin, :confirmed, organization: component.organization) }

                  it "shows the proposal" do
                    get :show, params: params.merge(id: emendation.id)
                    expect(response).to have_http_status(:ok)
                    expect(subject).to render_template(:show)
                  end
                end
              end
            end
          end

          context "and amendments VISIBILITY is set to 'all'" do
            before do
              component.update!(step_settings: { active_step_id => { amendments_visibility: "all" } })
            end

            context "when the user is not logged in" do
              it "shows the proposal" do
                get :show, params: params.merge(id: emendation.id)
                expect(response).to have_http_status(:ok)
                expect(subject).to render_template(:show)
              end
            end

            context "when the user is logged in" do
              before { sign_in user }

              context "and is NOT the author of the emendation" do
                it "shows the proposal" do
                  get :show, params: params.merge(id: emendation.id)
                  expect(response).to have_http_status(:ok)
                  expect(subject).to render_template(:show)
                end
              end
            end
          end
        end
      end
    end
  end
end
