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

require 'spec_helper'


class NoWhyrunDemonstrator < Chef::Provider
  attr_reader :system_state_altered
  def whyrun_supported?
    false
  end
  def load_current_resource

  end
  def action_foo
    @system_state_altered = true
  end
end

class ConvergeActionDemonstrator < Chef::Provider
  attr_reader :system_state_altered

  def whyrun_supported?
    true
  end

  def load_current_resource
  end

  def action_foo
    converge_by("running a state changing action") do
      @system_state_altered = true
    end
  end
end

describe Chef::Provider do
  let(:cookbook_collection) { Chef::CookbookCollection.new([]) }

  let(:node) do
    n = Chef::Node.new
    n.name "latte"
    n
  end

  let(:events) { Chef::EventDispatch::Dispatcher.new }

  let(:run_context) { Chef::RunContext.new(node, cookbook_collection, events) }

  let(:resource) do
    res = Chef::Resource.new("funk", run_context)
    res.cookbook_name = "a_delicious_pie"
    res
  end

  let(:provider) { Chef::Provider.new(resource, run_context, :nothing) }

  it "should mixin shell_out" do
    expect(provider.respond_to?(:shell_out)).to be true
  end

  it "should mixin shell_out!" do
    expect(provider.respond_to?(:shell_out!)).to be true
  end

  it "should mixin shell_out_with_systems_locale" do
    expect(provider.respond_to?(:shell_out_with_systems_locale)).to be true
  end

  it "should store the resource passed to new as new_resource" do
    provider.new_resource.should eql(resource)
  end

  it "should store the node passed to new as node" do
    provider.node.should eql(node)
  end

  it "should have nil for current_resource by default" do
    provider.current_resource.should eql(nil)
  end

  it "should not support whyrun by default" do
    provider.send(:whyrun_supported?).should eql(false)
  end

  it "should return true for action_nothing" do
    provider.action_nothing.should eql(true)
  end

  it "evals embedded recipes with a pristine resource collection" do
    provider.run_context.instance_variable_set(:@resource_collection, "doesn't matter what this is")
    temporary_collection = nil
    snitch = Proc.new {temporary_collection = run_context.resource_collection}
    provider.send(:recipe_eval, &snitch)
    expect(temporary_collection).to be_an_instance_of(Chef::ResourceCollection)
    expect(provider.run_context.instance_variable_get(:@resource_collection)).to eq "doesn't matter what this is"
  end

  describe "when creating the temporary run context" do
    let(:run_context) do
      rc = Chef::RunContext.new(node, cookbook_collection, events)
      # we actually want to test that RunContext#load is never called, but we
      # can't stub all instances of an object with rspec's mocks. :/
      allow(Chef::RunContext).to receive(:new).and_raise("not supposed to happen again")
      rc
    end
    let(:snitch) { Proc.new { temporary_collection = run_context.resource_collection } }

    it "does not re-load recipes" do
      provider.send(:recipe_eval, &snitch)
    end
  end

  context "when no converge actions are queued" do
    before do
      allow(provider).to receive(:whyrun_supported?).and_return(true)
      allow(provider).to receive(:load_current_resource)
    end

    it "does not mark the new resource as updated" do
      expect(resource).to_not be_updated
      expect(resource).to_not be_updated_by_last_action
    end
  end

  context "when converge actions have been added to the queue" do
    describe "and provider supports whyrun mode" do
      let(:provider) { ConvergeActionDemonstrator.new(resource, run_context, :foo) }

      it "should tell us that it does support whyrun" do
        expect(provider).to be_whyrun_supported
      end

      it "queues up converge actions" do
        provider.action_foo
        expect(provider.send(:converge_actions)).to have(1).actions
      end

      it "executes pending converge actions to converge the system" do
        provider.run_action
        expect(provider.instance_variable_get(:@system_state_altered)).to be_true
      end

      it "marks the resource as updated" do
        provider.run_action
        expect(resource).to be_updated
        expect(resource).to be_updated_by_last_action
      end
    end

    describe "and provider does not support whyrun mode" do
      let(:provider) { NoWhyrunDemonstrator.new(resource, run_context, :foo) }

      before do
        Chef::Config[:why_run] = true
      end

      after do
        Chef::Config[:why_run] = false
      end

      it "should tell us that it doesn't support whyrun" do
        expect(provider).to_not be_whyrun_supported
      end

      it "should automatically generate a converge_by block on the provider's behalf" do
        provider.run_action
        expect(provider.send(:converge_actions)).to have(0).actions
        expect(provider.system_state_altered).to be_false
      end

      it "should automatically execute the generated converge_by block" do
        provider.run_action
        expect(provider.system_state_altered).to be_false
        expect(resource).to_not be_updated
        expect(resource).to_not be_updated_by_last_action
      end
    end
  end

end
