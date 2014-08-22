require 'logger'
require 'sinatra'
require 'pivotal-tracker'
require 'digest'
require 'cgi'

ACTIVE_STATES = [:unstarted, :rejected, :started].freeze

STATE_FORWARD_TRANSITION = {
  rejected: :started,
  unstarted: :started,
  started: :finished,
  finished: :delivered,
  delivered: :accepted
}.freeze

STATES = [:unstarted, :rejected, :started, :finished, :delivered].freeze

DEFAULT_PROFILE_IMAGES = {
    'george@placed.com' => CGI.escape('http://4.bp.blogspot.com/-Q8gBxP-bIWE/UIUQxrlWtVI/AAAAAAAAHqI/XB_lHiygXt4/s640/cats_animals_little_kittens_kitten_kitty_cat_adorable_desktop_1920x1080_hd-wallpaper-782249.jpeg'),
    'jeremy@placed.com' => CGI.escape('http://bananajoke.com/uploads/2012/06/Crazy-Cat.jpg'),
    'mike@placed.com' => CGI.escape('http://www.jeffbullas.com/wp-content/uploads/2013/05/How-to-herd-casts-on-Twitter-1.jpg'),
    'nick@placed.com' => CGI.escape('http://static.guim.co.uk/sys-images/Guardian/Pix/pictures/2013/10/29/1383067928482/Grumpy-Cat-Tardar-Sauce-001.jpg'),
    'dillon@placed.com' => CGI.escape('http://cl.jroo.me/z3/Z/S/7/d/a.baa-One-cute-little-cat.jpg'),
    'carrie@placed.com' => CGI.escape('http://sewichi-test.s3.amazonaws.com/brad/images/cat.png'),
    'tim@placed.com' => CGI.escape('http://rigor.com/wp-content/uploads/2013/01/business-cat.jpg')
}.freeze

NICKNAMES = {
    'brad@placed.com' => 'B-rad',
    'george@placed.com' => 'The_Shredder',
    'jeremy@placed.com' => 'J-Treezy',
    'mike@placed.com' => 'Chaos_Monkey_Mike',
    'nick@placed.com' => 'KSP_Master',
    'will@placed.com' => 'The_Beebster',
    'dillon@placed.com' => 'Master_Intern'
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

  # TODO: I don't like that we are special casing this right here, but for now it at least fixes the issue
  if story.story_type == 'chore' && story.current_state == 'started'
    story.current_state = 'accepted'
  else
    story.current_state = STATE_FORWARD_TRANSITION[story.current_state.to_sym].to_s
  end

  logger.info("transitioning story #{story.id} from #{old_state} to #{story.current_state}")
  story.update
  redirect "/project/#{params[:project_id]}##{params[:dev_target]}"
end

post '/project/:project_id/stories/:story_id/blocked' do
  story = PivotalTracker::Story.find(params[:story_id], params[:project_id])
  raise "unknown story" if story.nil?
  redirect "/project/#{params[:project_id]}"
end
