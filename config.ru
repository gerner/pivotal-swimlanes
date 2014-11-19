require "rubygems"
require "sinatra"

require File.expand_path '../swimlanes.rb', __FILE__

map ('/swimlanes') { run Swimlanes }
