describe FloatingIpController do
  include_examples :shared_examples_for_floating_ip_controller, %w(openstack azure google amazon)

  let(:admin_user) { FactoryBot.create(:user, :role => "super_administrator") }
  let(:ems) { FactoryBot.create(:ems_openstack).network_manager }
  let(:floating_ip) { FactoryBot.create(:floating_ip_openstack, :ext_management_system => ems) }

  before do
    login_as admin_user
    EvmSpecHelper.create_guid_miq_server_zone
  end

  describe "#tagging_edit" do
    before do
      @ct = FactoryBot.create(:floating_ip)
      allow(@ct).to receive(:tagged_with).with(:cat => admin_user.userid).and_return("my tags")
      classification = FactoryBot.create(:classification, :name => "department", :description => "Department")
      @tag1 = FactoryBot.create(:classification_tag,
                                 :name   => "tag1",
                                 :parent => classification)
      @tag2 = FactoryBot.create(:classification_tag,
                                 :name   => "tag2",
                                 :parent => classification)
      allow(Classification).to receive(:find_assigned_entries).with(@ct).and_return([@tag1, @tag2])
      session[:tag_db] = "FloatingIp"
      edit = {
        :key        => "FloatingIp_edit_tags__#{@ct.id}",
        :tagging    => "FloatingIp",
        :object_ids => [@ct.id],
        :current    => {:assignments => []},
        :new        => {:assignments => [@tag1.id, @tag2.id]}
      }
      session[:edit] = edit
    end

    after(:each) do
      expect(response.status).to eq(200)
    end

    it "builds tagging screen" do
      post :button, :params => { :pressed => "floating_ip_tag", :format => :js, :id => @ct.id }
      expect(assigns(:flash_array)).to be_nil
    end

    it "cancels tags edit" do
      session[:breadcrumbs] = [{:url => "floating_ip/show/#{@ct.id}"}, 'placeholder']
      post :tagging_edit, :params => { :button => "cancel", :format => :js, :id => @ct.id }
      expect(assigns(:flash_array).first[:message]).to include("was cancelled by the user")
      expect(assigns(:edit)).to be_nil
    end

    it "save tags" do
      session[:breadcrumbs] = [{:url => "floating_ip/show/#{@ct.id}"}, 'placeholder']
      post :tagging_edit, :params => { :button => "save", :format => :js, :id => @ct.id, :data => get_tags_json([@tag1, @tag2]) }
      expect(assigns(:flash_array).first[:message]).to include("Tag edits were successfully saved")
      expect(assigns(:edit)).to be_nil
    end
  end

  describe "#show" do
    subject { get :show, :params => {:id => floating_ip.id} }

    context "render listnav partial" do
      render_views

      it do
        is_expected.to have_http_status 200
      end
    end
  end

  describe "#create" do
    let(:task_options) do
      {
        :action => "creating Floating IP for user %{user}" % {:user => controller.current_user.userid},
        :userid => controller.current_user.userid
      }
    end
    let(:queue_options) do
      {
        :class_name  => ems.class.name,
        :method_name => 'create_floating_ip',
        :instance_id => ems.id,
        :args        => [{}]
      }
    end

    it "builds create screen" do
      post :button, :params => { :pressed => "floating_ip_new", :format => :js }
      expect(assigns(:flash_array)).to be_nil
    end
  end

  describe "#edit" do
    let(:task_options) do
      {
        :action => "updating Floating IP for user %{user}" % {:user => controller.current_user.userid},
        :userid => controller.current_user.userid
      }
    end
    let(:queue_options) do
      {
        :class_name  => floating_ip.class.name,
        :method_name => 'raw_update_floating_ip',
        :instance_id => floating_ip.id,
        :args        => [{:network_port_ems_ref => ""}]
      }
    end

    it "builds edit screen" do
      post :button, :params => { :pressed => "floating_ip_edit", :format => :js, :id => floating_ip.id }
      expect(assigns(:flash_array)).to be_nil
    end
  end

  describe "#delete_floating_ips" do
    before do
      allow(controller).to receive(:assert_privileges)
      allow(controller).to receive(:performed?)
      controller.params = {:id => floating_ip.id, :pressed => 'host_NECO'}
    end

    it 'calls process_floating_ips' do
      expect(controller).to receive(:process_floating_ips).with([floating_ip], "destroy")
      controller.send(:delete_floating_ips)
    end
  end

  describe '#button' do
    before { controller.params = params }

    context 'deleting selected Floating IP' do
      let(:params) { {:pressed => 'floating_ip_delete'} }
      let(:task_options) do
        {
          :action => "deleting Floating IP for user %{user}" % {:user => controller.current_user.userid},
          :userid => controller.current_user.userid
        }
      end
      let(:queue_options) do
        {
          :class_name  => floating_ip.class.name,
          :method_name => 'raw_delete_floating_ip',
          :instance_id => floating_ip.id,
          :args        => []
        }
      end

      it 'calls delete_floating_ips' do
        expect(controller).to receive(:delete_floating_ips)
        controller.send(:button)
      end

      it "queues the delete action" do
        expect(MiqTask).to receive(:generic_action_with_callback).with(task_options, hash_including(queue_options))
        post :button, :params => {:id => floating_ip.id, :pressed => "floating_ip_delete", :format => :js}
      end
    end

    context 'managing the port association of a Floating IP' do
      let(:params) { {:pressed => 'floating_ip_edit', :id => floating_ip.id.to_s} }

      it 'redirects to edit method' do
        expect(controller).to receive(:javascript_redirect).with(:action => 'edit', :id => floating_ip.id.to_s)
        controller.send(:button)
      end
    end

    context 'adding new Floating IP' do
      let(:params) { {:pressed => 'floating_ip_new'} }

      it 'redirects to new method' do
        expect(controller).to receive(:javascript_redirect).with(:action => 'new')
        controller.send(:button)
      end
    end

    context 'tagging selected Floating IPs' do
      let(:params) { {:pressed => 'floating_ip_tag', :miq_grid_checks => floating_ip.id.to_s} }

      it 'calls tag method' do
        expect(controller).to receive(:tag).with(FloatingIp)
        controller.send(:button)
      end
    end
  end
  it_behaves_like "Set Default in search bar"
end
