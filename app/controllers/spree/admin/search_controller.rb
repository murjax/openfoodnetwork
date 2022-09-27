# frozen_string_literal: true

module Spree
  module Admin
    class SearchController < Spree::Admin::BaseController
      # http://spreecommerce.com/blog/2010/11/02/json-hijacking-vulnerability/
      before_action :check_json_authenticity, only: :index
      respond_to :json

      def known_users
        @users = if exact_match = Spree::User.find_by(email: search_params[:q])
                   [exact_match]
                 else
                   spree_current_user.known_users.ransack(ransack_hash).result.limit(10)
                 end

        render json: @users, each_serializer: ::Api::Admin::UserSerializer
      end

      def customers
        @customers = []
        if enterprises.where(id: search_params[:distributor_id].to_i).present?
          @customers = Customer.
            ransack(m: 'or', email_start: search_params[:q], first_name_start: search_params[:q],
                    last_name_start: search_params[:q]).
            result.
            where(enterprise_id: search_params[:distributor_id].to_i)
        end
        render json: @customers, each_serializer: ::Api::Admin::CustomerSerializer
      end

      private

      def ransack_hash
        {
          m: 'or',
          email_start: search_params[:q],
          ship_address_firstname_start: search_params[:q],
          ship_address_lastname_start: search_params[:q],
          bill_address_firstname_start: search_params[:q],
          bill_address_lastname_start: search_params[:q]
        }
      end

      def search_params
        params.permit(:q, :distributor_id).to_h.with_indifferent_access
      end

      def enterprises
        if spree_current_user.admin?
          Enterprise.all
        else
          spree_current_user.enterprises
        end
      end
    end
  end
end
