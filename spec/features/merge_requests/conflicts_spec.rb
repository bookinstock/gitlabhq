require 'spec_helper'

feature 'Merge request conflict resolution', :js do
  let(:user) { create(:user) }
  let(:project) { create(:project, :repository) }

  before do
    # In order to have the diffs collapsed, we need to disable the increase feature
    stub_feature_flags(gitlab_git_diff_size_limit_increase: false)
  end

  def create_merge_request(source_branch)
    create(:merge_request, source_branch: source_branch, target_branch: 'conflict-start', source_project: project) do |mr|
      mr.mark_as_unmergeable
    end
  end

  shared_examples "conflicts are resolved in Interactive mode" do
    it 'conflicts are resolved in Interactive mode' do
      within find('.files-wrapper .diff-file', text: 'files/ruby/popen.rb') do
        click_button 'Use ours'
      end

      within find('.files-wrapper .diff-file', text: 'files/ruby/regex.rb') do
        all('button', text: 'Use ours').each do |button|
          button.trigger('click')
        end
      end

      click_button 'Commit conflict resolution'

      expect(page).to have_content('All merge conflicts were resolved')
      merge_request.reload_diff

      wait_for_requests

      click_on 'Changes'
      wait_for_requests

      within find('.diff-file', text: 'files/ruby/popen.rb') do
        expect(page).to have_selector('.line_content.new', text: "vars = { 'PWD' => path }")
        expect(page).to have_selector('.line_content.new', text: "options = { chdir: path }")
      end

      within find('.diff-file', text: 'files/ruby/regex.rb') do
        expect(page).to have_selector('.line_content.new', text: "def username_regexp")
        expect(page).to have_selector('.line_content.new', text: "def project_name_regexp")
        expect(page).to have_selector('.line_content.new', text: "def path_regexp")
        expect(page).to have_selector('.line_content.new', text: "def archive_formats_regexp")
        expect(page).to have_selector('.line_content.new', text: "def git_reference_regexp")
        expect(page).to have_selector('.line_content.new', text: "def default_regexp")
      end
    end
  end

  shared_examples "conflicts are resolved in Edit inline mode" do
    it 'conflicts are resolved in Edit inline mode' do
      expect(find('#conflicts')).to have_content('popen.rb')

      within find('.files-wrapper .diff-file', text: 'files/ruby/popen.rb') do
        click_button 'Edit inline'
        wait_for_requests
        find('.files-wrapper .diff-file pre')
        execute_script('ace.edit($(".files-wrapper .diff-file pre")[0]).setValue("One morning");')
      end

      within find('.files-wrapper .diff-file', text: 'files/ruby/regex.rb') do
        click_button 'Edit inline'
        wait_for_requests
        find('.files-wrapper .diff-file pre')
        execute_script('ace.edit($(".files-wrapper .diff-file pre")[1]).setValue("Gregor Samsa woke from troubled dreams");')
      end

      click_button 'Commit conflict resolution'

      expect(page).to have_content('All merge conflicts were resolved')
      merge_request.reload_diff

      wait_for_requests

      click_on 'Changes'
      wait_for_requests

      expect(page).to have_content('One morning')
      expect(page).to have_content('Gregor Samsa woke from troubled dreams')
    end
  end

  context 'can be resolved in the UI' do
    before do
      project.team << [user, :developer]
      sign_in(user)
    end

    context 'the conflicts are resolvable' do
      let(:merge_request) { create_merge_request('conflict-resolvable') }

      before do
        visit project_merge_request_path(project, merge_request)
      end

      it 'shows a link to the conflict resolution page' do
        expect(page).to have_link('conflicts', href: /\/conflicts\Z/)
      end

      context 'in Inline view mode' do
        before do
          click_link('conflicts', href: /\/conflicts\Z/)
        end

        include_examples "conflicts are resolved in Interactive mode"
        include_examples "conflicts are resolved in Edit inline mode"
      end

      context 'in Parallel view mode' do
        before do
          click_link('conflicts', href: /\/conflicts\Z/)
          click_button 'Side-by-side'
        end

        include_examples "conflicts are resolved in Interactive mode"
        include_examples "conflicts are resolved in Edit inline mode"
      end
    end

    context 'the conflict contain markers' do
      let(:merge_request) { create_merge_request('conflict-contains-conflict-markers') }

      before do
        visit project_merge_request_path(project, merge_request)
        click_link('conflicts', href: /\/conflicts\Z/)
      end

      it 'conflicts can not be resolved in Interactive mode' do
        within find('.files-wrapper .diff-file', text: 'files/markdown/ruby-style-guide.md') do
          expect(page).not_to have_content 'Interactive mode'
          expect(page).not_to have_content 'Edit inline'
        end
      end

      it 'conflicts are resolved in Edit inline mode' do
        within find('.files-wrapper .diff-file', text: 'files/markdown/ruby-style-guide.md') do
          wait_for_requests
          find('.files-wrapper .diff-file pre')
          execute_script('ace.edit($(".files-wrapper .diff-file pre")[0]).setValue("Gregor Samsa woke from troubled dreams");')
        end

        click_button 'Commit conflict resolution'

        expect(page).to have_content('All merge conflicts were resolved')

        merge_request.reload_diff

        wait_for_requests

        click_on 'Changes'
        wait_for_requests
        click_link 'Expand all'
        wait_for_requests

        expect(page).to have_content('Gregor Samsa woke from troubled dreams')
      end
    end
  end

  UNRESOLVABLE_CONFLICTS = {
    'conflict-too-large' => 'when the conflicts contain a large file',
    'conflict-binary-file' => 'when the conflicts contain a binary file',
    'conflict-missing-side' => 'when the conflicts contain a file edited in one branch and deleted in another',
    'conflict-non-utf8' => 'when the conflicts contain a non-UTF-8 file'
  }.freeze

  UNRESOLVABLE_CONFLICTS.each do |source_branch, description|
    context description do
      let(:merge_request) { create_merge_request(source_branch) }

      before do
        project.team << [user, :developer]
        sign_in(user)

        visit project_merge_request_path(project, merge_request)
      end

      it 'does not show a link to the conflict resolution page' do
        expect(page).not_to have_link('conflicts', href: /\/conflicts\Z/)
      end

      it 'shows an error if the conflicts page is visited directly' do
        visit current_url + '/conflicts'
        wait_for_requests

        expect(find('#conflicts')).to have_content('Please try to resolve them locally.')
      end
    end
  end
end
