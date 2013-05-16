#!/usr/bin/env ruby

require 'ruby-mpd'
require 'diff/lcs/array'

class Enslaver
  def initialize(master_host, slave_host)
    @idle = MPD.new master_host
    @master = MPD.new master_host
    @master.on :playlist do |pl|
      playlist
    end
    @master.on :volume do |vol|
      volume
    end
    @master.on :error do |e|
      puts 'master error'
      puts e
    end

    @slave = MPD.new slave_host
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
    ch=dst.map{|x| x.file}.sdiff(src.map{|x| x.file})
    ch.reverse.each{|x| (puts @slave.delete(dst[x.old_position].pos) rescue []) if "!-".index x.action}.length
    ch.each{|x| e=src[x.new_position]; (puts @slave.addid(e.file, e.pos) rescue []) if "!+".index x.action}.length
  end

  def player
    src=@master.status
    dst=@slave.status
    puts src
    puts dst
    if @master.stopped?
      puts 'stop'
      @slave.stop
    elsif dst.has_key?(:nextsongid) and src[:song] == dst[:nextsongid] and dst.has_key?(:time) and src[:time][0] + dst[:time][1] - dst[:time][0] < 5
      puts 'continue'
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
      if (src[:time][0] - dst[:time][0]).abs > 3
        puts 'seek'
        @slave.seek(src[:time][0], {:pos => src[:song]})
      end
    end
  end

  def output
    prepare
    dst=@slave.outputs
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

  def prepare
    @slave.connect unless @slave.connected?
    @master.connect unless @master.connected?
    @idle.connect unless @idle.connected?
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
        prepare
        puts @idle.send_command :idle
      rescue
        puts $!
        sleep 5
      end
    end
  end
    
  def main sin
    @act = Thread.new { act { Thread.stop if @run_done >= @run; @run_done = @run; sleep 0.05 } }
    @act.run
    while true
      begin
        prepare
        if sin 
          i = gets.chomp.to_sym
        else
          i = @idle.send_command :idle
        end
        puts i
        case i
        when :mixer
          @mixer+=1
        when :playlist
          @playlist+=1
        when :player
          @player+=1
        when :output
          @output+=1
        else
          puts "Nothing"
          next
        end
        @run+=1
        @act.run
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
