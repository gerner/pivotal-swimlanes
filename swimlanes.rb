require 'logger'
require 'sinatra'
require 'pivotal-tracker'

ACTIVE_STATES = [:unstarted, :rejected, :started]
STATE_FORWARD_TRANSITION = {
  unstarted: :started,
  started: :finished,
  finished: :delivered,
  delivered: :accepted
}

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

  def points_total
    return @points_total unless @points_total.nil?
    @points_total = stories.reduce(0) do |tot, s|
      tot + ((s.estimate.nil?)?0:s.estimate)
    end
  end

  def points_left
    return @points_left unless @points_left.nil?
    @points_left = stories.reduce(0) do |tot, s|
      tot + ((s.estimate.nil? || !ACTIVE_STATES.include?(s.current_state.to_sym))?0:s.estimate)
    end
  end

  def stories
    return @stories unless @stories.nil?
    states = [:unstarted, :rejected, :started, :finished, :delivered]
    stories = project.stories.all({owner: member.initials, state: states})
  end

  def self.all(project, stories)
    developers = PivotalTracker::Membership.all(project).map do |m|
      owned_stories = stories.select { |s| s.owned_by == m.name }
      Developer.new({member: m, project: project, stories: owned_stories})
    end
  end

end

helpers do
  def stories_for_state(stories, state)
    s = stories.select { |s| s.current_state.to_sym == state }
    #if state == :unstarted
    #  s = s[0..1]
    #end
    return s
  end
end

enable :sessions

configure do
end

before do
  session[:token] = params[:token] unless params[:token].nil?
  PivotalTracker::Client.token = session[:token]
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
  story.current_state = STATE_FORWARD_TRANSITION[story.current_state.to_sym].to_s
  logger.info("transitioning story #{story.id} from #{old_state} to #{story.current_state}")
  story.update
  redirect "/project/#{params[:project_id]}"
end

post '/project/:project_id/stories/:story_id/blocked' do
  story = PivotalTracker::Story.find(params[:story_id], params[:project_id])
  raise "unknown story" if story.nil?
  redirect "/project/#{params[:project_id]}"
end
