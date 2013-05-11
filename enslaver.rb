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
  end

  def mixer
    prepare
    @slave.volume=@master.volume
  end

  def playlist
    prepare
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
    elsif dst.has_key?(:nextsongid) and src[:song] == dst[:nextsongid] and src[:time][0] + dst[:time][1] - dst[:time][0] < 5
      puts 'continue'
    else
      if dst.has_key?(:song) and src[:song] == dst[:song]
        puts 'paused?'
        @slave.pause=@master.paused?
        if @master.paused?
          return
        end
      else
        puts 'play'
        @slave.play(src[:song])
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

  def main
    while true
      begin
        prepare
        i = @idle.send_command('idle')
        puts i
        case i
        when :mixer
          mixer
        when :playlist
          playlist
        when :player
          player
        when :output
          output
        end
      rescue
        puts $!
        sleep 1
      end
    end
  end
end

Enslaver.new('pong', 'pung').main
