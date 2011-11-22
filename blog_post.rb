#!/usr/bin/env ruby
require 'rubygems'
require 'sinatra'
set :markdown, :layout_engine => :erb

get '/' do
  markdown :NArrayBlogPost
end
