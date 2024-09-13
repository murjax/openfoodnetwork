# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BackorderJob do
  let(:order) { create(:completed_order_with_totals) }
  let(:variant) { order.variants.first }
  let(:user) { order.distributor.owner }
  let(:product_link) {
    "https://env-0105831.jcloud-ver-jpe.ik-server.com/api/dfc/Enterprises/test-hodmedod/SuppliedProducts/44519466467635"
  }

  before do
    user.oidc_account = OidcAccount.new(
      uid: "testdfc@protonmail.com",
      refresh_token: ENV.fetch("OPENID_REFRESH_TOKEN"),
      updated_at: 1.day.ago,
    )
  end

  describe ".check_stock" do
    it "ignores products without semantic link" do
      BackorderJob.check_stock(order) # and not web requests were made
    end

    it "places an order", vcr: true do
      order.order_cycle = create(
        :simple_order_cycle,
        distributors: [order.distributor],
        variants: [variant],
      )
      completion_time = order.order_cycle.orders_close_at + 1.minute
      variant.on_demand = true
      variant.on_hand = -3
      variant.semantic_links << SemanticLink.new(
        semantic_id: product_link
      )

      expect {
        BackorderJob.check_stock(order)
      }.to enqueue_job(CompleteBackorderJob).at(completion_time)

      # We ordered a case of 12 cans: -3 + 12 = 9
      expect(variant.on_hand).to eq 9

      # Clean up after ourselves:
      perform_enqueued_jobs(only: CompleteBackorderJob)
    end
  end

  describe ".place_order" do
    it "schedules backorder completion for specific enterprises" do
      order.order_cycle = build(
        :simple_order_cycle,
        id: 1,
        orders_close_at: Date.tomorrow.noon,
      )
      completion_time = Date.tomorrow.noon + 4.hours

      orderer = FdcBackorderer.new(user)
      backorder = orderer.build_new_order(order)
      backorder.client = "https://openfoodnetwork.org.uk/api/dfc/enterprises/203468"

      expect(orderer).to receive(:send_order).and_return(backorder)
      expect {
        BackorderJob.place_order(user, order, orderer, backorder)
      }.to enqueue_job(CompleteBackorderJob).at(completion_time)
    end
  end
end
