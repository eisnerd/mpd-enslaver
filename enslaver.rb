#!/usr/bin/env ruby

require 'ruby-mpd'
require 'diff/lcs/array'

class Enslaver
  def initialize(master_host, slave_host)
    @linked = false
    @master_host = master_host
    @idle = MPD.new @master_host
    @master = MPD.new @master_host
    #@master.on :playlist do |pl|
    #  playlist
    #end
    #@master.on :volume do |vol|
    #  volume
    #end
    @master.on :error do |e|
      puts 'master error'
      puts e
    end

    @slave_host = slave_host
    @slave = MPD.new @slave_host
    @slave.on :error do |e|
      puts 'slave error'
      puts e
    end
    @mixer = 1
    @playlist = 1
    @player = 1
    @output = 1
    @mixer_done = 0
    @playlist_done = 0
    @player_done = 0
    @output_done = 0
    @run = 0
    @run_done = 0
  end

  def mixer
    prepare
    puts "Setting volume"
    @slave.volume=@master.volume
  end

  def playlist
    prepare
    puts "Comparing playlists"
    src=@master.queue
    dst=@slave.queue
    puts "#{src.length} vs #{dst.length}"
    ch=dst.map{|x| x.file}.sdiff(src.map{|x| x.file})
    puts ch.select{|x| x.action != "="}.map(&:inspect)
    ch.reverse.each{|x| (puts @slave.delete(dst[x.old_position].pos) rescue []) if "!-".index x.action}.length
    ch.each{|x| e=src[x.new_position]; print e.file, " as ", (@slave.addid(e.file, e.pos) rescue []), "\n" if "!+".index x.action}.length
    puts "Playlists reconciled"
  end

  def player
    begin
      player_
    rescue
      puts $!
      playlist
      player_
    end
  end

  def player_
    src=@master.status
    dst=@slave.status
    puts src
    puts dst
    if @master.stopped?
      puts 'stop'
      @slave.stop
    elsif dst.has_key?(:nextsong) and src[:song] == dst[:nextsong] and dst.has_key?(:time) and src[:time][0] + dst[:time][1] - dst[:time][0] < 5
      puts 'continue dst'
    elsif src.has_key?(:nextsong) and dst[:song] == src[:nextsong] and src.has_key?(:time) and dst[:time][0] + src[:time][1] - src[:time][0] < 5
      puts 'continue src'
    else
      if not dst.has_key?(:song) or src[:song] != dst[:song]
        puts 'play'
        @slave.play(src[:song])
      end
      puts 'paused?'
      @slave.pause=@master.paused?
      if @master.paused?
        return
      end
      dst=@slave.status
      if src.has_key?(:time) and (!dst.has_key?(:time) or (src[:time][0] - dst[:time][0]).abs > 3)
        puts 'seek'
        @slave.seek(src[:time][0], {:pos => src[:song]})
      end
    end
  end

  def output
    preparo
    dst=@slave.outputs
    puts dst, dst.length
    @master.outputs.each{|x|
      dst.each{|y|
        if x[:outputname] == y[:outputname] and x[:outputenabled] != y[:outputenabled]
          if x[:outputenabled]
            @slave.enableoutput(y[:outputid])
          else
            @slave.disableoutput(y[:outputid])
          end
        end
      }
    }
  end

  def preparo
    begin
      @slave.connect unless @slave.connected?
      @master.connect unless @master.connected?
      @idle.connect unless @idle.connected?
    rescue
      puts $!
      sleep 2
      @idle = MPD.new @master_host
      @master = MPD.new @master_host
      @slave = MPD.new @slave_host
      preparo
    end
  end

  def prepare
    preparo
    dst = @slave.outputs.map{|i| i[:outputname]}
    # raise "Not linked" unless @master.channels.any? {|c| dst.include? c}
    [@master.list_stickers("global", "slaves")].flatten.each {|a|
     begin
      as=a.to_s.split('=')
      b=@slave.get_sticker("global", "slaves", as[0]).to_s.split('=')[1].to_i rescue 0
      @slave.set_sticker("global", "slaves", as[0], as[1]+"="+as[2]) if as[1].to_i > b
     rescue; end
    }
    raise "Not linked" unless [@master.list_stickers("global", "slaves")].flatten.any? {|c| (cs=c.to_s.split('='); cs[2] == "on" and dst.include? cs[0]) rescue false }
  end

  def act
    while true
     begin
      puts [@playlist, @output, @mixer, @player].to_s
      if @playlist_done < @playlist
        @playlist_done = @playlist
        playlist
      end
      if @output_done < @output
        @output_done = @output
        output
      end
      if @mixer_done < @mixer
        @mixer_done = @mixer
        mixer
      end
      if @player_done < @player
        @player_done = @player
        player
      end
      yield if block_given?
     rescue
      puts $!
      puts $!.backtrace
      sleep 1
     end
    end
  end

  def listen
    while true
      begin
        preparo
        puts @idle.send_command :idle
      rescue
        puts $!
        sleep 5
      end
    end
  end
    
  def main sin
          playlist rescue []
          mixer rescue []
          output rescue []
          player rescue []
    while true
      begin
        preparo
        if sin 
          i = gets.chomp.to_sym
        else
          i = @idle.send_command :idle
        end
        puts i
        for j in [i].flatten
        case j
        when :mixer
          mixer
	when :sticker
	  playlist
	  mixer
	  output
	  player
        when :playlist
          playlist
          mixer
          output
          player
        when :player
          mixer
          output
          player
        when :output
          mixer rescue []
          output
          player
        else
          puts "Nothing: #{i}"
          next
        end rescue []
        end
      rescue
        puts $!
        puts $!.backtrace
        sleep 1
      end
    end
  end
end

e=Enslaver.new('pong', 'pung')
if ARGV.delete('-l')
  e.listen
else
  e.main ARGV.delete('-s')
end
