#!/usr/bin/env ruby

require 'pivotal-tracker'

PivotalTracker::Client.token = ARGV[0]

project_id = ARGV[1]

project = PivotalTracker::Project.find(project_id)
members = PivotalTracker::Membership.all(project)

STATES = [:unstarted, :rejected, :started, :finished, :delivered]

line = "owner\t"
STATES.each { |state| line += "#{state}\t" }
puts line

members.each do |m|
  stories = project.stories.all({owner: m.initials, state: STATES})
  next if stories.empty?
  stories_by_state = {}
  STATES.each { |state| stories_by_state[state] = [] }

  points_to_go = 0
  points_total = 0
  stories.each do |s|
    current_state = s.current_state.to_sym
    unless s.estimate.nil?
      points_to_go += s.estimate if [:unstarted, :rejected, :started].include? current_state
      points_total += s.estimate
    end
    stories_by_state[current_state] << s if stories_by_state.key? current_state
  end

  puts "#{m.name} (#{points_to_go}/#{points_total} in #{stories.size})"+"\t|   "+STATES.join("\t|   ")

  stories_left = stories.size
  while stories_left > 0
    line = "\t"
    STATES.each do |state|
      line += (stories_by_state[state].empty?) ? "|\t" : "| #{stories_by_state[state].pop.name}\t"
      stories_left -= 1
    end
    puts line
  end
  puts ""

end


