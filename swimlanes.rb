require 'logger'
require 'sinatra'
require 'pivotal-tracker'
require 'digest'
require 'cgi'
require 'sinatra/config_file'

ACTIVE_STATES = [:unstarted, :rejected, :started].freeze

STATE_FORWARD_TRANSITION = {
  rejected: :started,
  unstarted: :started,
  started: :finished,
  finished: :delivered,
  delivered: :accepted
}.freeze

STATES = [:unstarted, :rejected, :started, :finished, :delivered].freeze

DEFAULT_PROFILE_IMAGES = {}

NICKNAMES = {}

logger = Logger.new(STDERR)

class Developer
  attr_reader :member, :project

  def initialize(opts = {})
    @member = opts[:member]
    @project = opts[:project]
    @stories = opts[:stories]
    @points_total = nil
    @points_left = nil
  end

  def gravatar(size = 80)
    @gravatar ||= "http://www.gravatar.com/avatar/#{email_hash}?s=#{size}&d=#{DEFAULT_PROFILE_IMAGES[@member.email.downcase]}"
  end

  def nickname
    @nickname ||= NICKNAMES[@member.email.downcase]
  end

  def email_hash
    @email_hash ||= Digest::MD5.hexdigest(@member.email.downcase)
  end

  def points_total
    @points_total ||= stories.reduce(0) do |tot, s|
      tot + ((s.estimate.nil?)?0:s.estimate)
    end
  end

  def points_left
    @points_left ||= stories.reduce(0) do |tot, s|
      tot + ((s.estimate.nil? || !ACTIVE_STATES.include?(s.current_state.to_sym))?0:s.estimate)
    end
  end

  def stories
    @stories ||= project.stories.all({owner: member.initials, state: STATES})
  end

  def self.all(project, stories)
    PivotalTracker::Membership.all(project).map do |m|
      owned_stories = stories.select { |s| s.owned_by == m.name }
      Developer.new({member: m, project: project, stories: owned_stories})
    end
  end
end

class Swimlanes < Sinatra::Base

  register Sinatra::ConfigFile

  config_file '/srv/swimlanes/config.yml'

  helpers do
    def stories_for_state(stories, state)
      s = stories.select { |s| s.current_state.to_sym == state }
      #if state == :unstarted
      #  s = s[0..1]
      #end
      return s
    end

    def next_state(state)
      STATE_FORWARD_TRANSITION[state].to_s.gsub('ed', '').capitalize
    end
  end

  enable :sessions

  configure do
    DEFAULT_PROFILE_IMAGES.merge!(Hash[ settings.users.reject { |k,v| v["profile_image"].nil? }.map { |k,v| [v["email"], CGI.escape(v["profile_image"])] } ])
    NICKNAMES.merge!(Hash[ settings.users.reject { |k,v| v["nickname"].nil? }.map { |k,v| [v["email"], CGI.escape(v["nickname"])] } ])
  end

  before do
    session[:token] = params[:token] unless params[:token].nil?
    PivotalTracker::Client.token = session[:token] || settings.token
  end

  get '/' do
    @token = session[:token]
    erb :index
  end

  get '/project' do
    @token = session[:token]
    @projects = PivotalTracker::Project.all
    erb :projects
  end

  get '/project/:project_id' do
    @states = [:unstarted, :rejected, :started, :finished, :delivered]
    conditional_states = [:rejected, :delivered]
    @project = PivotalTracker::Project.find(params[:project_id].to_i)
    @stories = @project.stories.all({state: @states})
    @states.delete_if {|s| conditional_states.include?(s) && stories_for_state(@stories, s).empty? }
    @developers = Developer.all(@project, @stories)
    erb :project
  end

  post '/project/:project_id/stories/:story_id/next' do
    story = PivotalTracker::Story.find(params[:story_id], params[:project_id])
    raise "unknown story" if story.nil?
    raise "#{story.current_state} has unknown next transition" if STATE_FORWARD_TRANSITION[story.current_state.to_sym].nil?
    old_state = story.current_state

    # TODO: I don't like that we are special casing this right here, but for now it at least fixes the issue
    if story.story_type == 'chore' && story.current_state == 'started'
      story.current_state = 'accepted'
    else
      story.current_state = STATE_FORWARD_TRANSITION[story.current_state.to_sym].to_s
    end

    logger.info("transitioning story #{story.id} from #{old_state} to #{story.current_state}")
    story.update
    redirect to("/project/#{params[:project_id]}##{params[:dev_target]}")
  end

  post '/project/:project_id/stories/:story_id/blocked' do
    story = PivotalTracker::Story.find(params[:story_id], params[:project_id])
    raise "unknown story" if story.nil?
    redirect to("/project/#{params[:project_id]}")
  end

  get '/project/:project_id/bug' do
    @requester = params[:submitter_override] || env['HTTP_X_FORWARDED_REMOTE_USER']
    @project = PivotalTracker::Project.find(params[:project_id].to_i)
    @submitted = params[:submitted]
    @labels = settings.bug_form["labels"]
    @bug_type = params[:type] || "bug"
    erb :bug_form
  end

  post '/project/:project_id/bug' do
    project = PivotalTracker::Project.find(params[:project_id].to_i)
    title = "#{params[:submitter_name]} - #{params[:title]}"

    user = settings.users[params[:submitter_name]]
    user_email = user["email"] if user
    requesting_developer = Developer.all(project, []).find { |d| d.member.email == user_email }

    logger.info("request #{title} submitted by #{params[:submitter_name]} with email #{user_email} with name #{requesting_developer ? requesting_developer.member.name : nil}")

    if requesting_developer
      project.stories.create(name: title, requested_by: requesting_developer.member.name, story_type: params[:type], description: params[:description], labels: params[:label])
    else
      project.stories.create(name: title, story_type: params[:type], description: params[:description], labels: params[:label])
    end
    redirect to("/project/#{params[:project_id]}/bug?submitted=true&type=#{params[:type]}")
  end

  run! if app_file == $0
end


