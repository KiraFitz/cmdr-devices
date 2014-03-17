# Copyright (C) 2014 Wesleyan University
#
# This file is part of cmdr-devices.
#
# cmdr-devices is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# cmdr-devices is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with cmdr-devices. If not, see <http://www.gnu.org/licenses/>.

#---
#{
#	"name": "PJLinkProjector",
#	"depends_on": "SocketProjector",
#	"description": "Controls any projector capable of understanding the PJLink protocol standard, ie. the Epson PowerLite Pro G5750WU",
#	"author": "Jonathan Lyons",
#	"email": "jclyons@wesleyan.edu",
# "type": "Projector"
#}
#---
require 'digest/md5'

class PJLinkProjector < SocketProjector  
  INPUT_HASH = {"HDMI" => 32, "YPBR" => 13, "RGB1" => 11, "VIDEO" => 23, "SVIDEO" => 22}

  configure do
    #DaemonKit.logger.info "@Initializing PJLinkProjector at URI #{options[:uri]} with name #{@name}"
  end

  def initialize(name, options)
    options = options.symbolize_keys
    @_password = options[:password]
    super(name, options)
  end

  # Generates the auth key for pjlink
  def read data
    EM.cancel_timer @_cooling_timer if @_cooling_timer
    @_cooling_timer = nil
    if data.start_with? "PJLINK 1"
      @_digest = Digest::MD5.hexdigest "#{data.chop[9..-1]}#{@_password}"
    end
    super data 
  end

  def send_string(string)
    string = @_digest+string if @_digest
    super string
  end

  def interpret_error(error)
    error.each_char do |e|
      if e == "1"
      elsif e == "2"
      end
    end
  end

	managed_state_var :power, 
		:type => :boolean,
		:display_order => 1,
		:action => proc{|on|
      "%1POWR #{on ? "1" : "0"}\r"
		}

	managed_state_var :input, 
		:type => :option,
		# Numbers correspond to HDMI, YPBR, RGB, RGB2, VID, and SVID in that order
		:options => [ 'HDMI', 'YPBR', 'RGB1', 'VID', 'SVID'],
		:display_order => 2,
		:action => proc{|source|
			"%1INPT #{INPUT_HASH[source]}\r"
		}

	managed_state_var :mute, 
		:type => :boolean,
		:action => proc{|on|
			"%1AVMT #{on ? "31" : "30"}\r"
		}

	managed_state_var :video_mute,
		:type => :boolean,
		:display_order => 4,
		:action => proc{|on|
			"%1AVMT #{on ? "31" : "30"}\r"
		}

	responses do
		#ack ":"
		error :general_error, "ERR", "Received an error"
    match :err_status, /%1ERST=(\d+)/, proc{|m|
        interpret_error m[1] if m[1] != "000000"
    }
		match :power,  /%1POWR=(.+)/, proc{|m|
	 		#DaemonKit.logger.info "Received power value #{m[1]}"
			  self.power = (m[1] == "1") 
	  		self.cooling = (m[1] == "2")
	  		self.warming = (m[1] == "3") || (m[1] == "ERR3")
		}
		#match :mute,       /%1AVMT=(.+)/, proc{|m| self.mute = (m[1] == "31")}
		match :video_mute, /%1AVMT=(.+)/, proc{|m| self.video_mute = (m[1] == "31")}
		match :input,      /%1INPT=(.+)/, proc{|m| self.input = m[1]}
    match :lamp_hours, /%1LAMP=(\d+) (\d)/, proc {|m|
        self.lamp_hours = m[1].to_i
        self.percent_lamp_used =((m[1].to_f / 2000) * 100).floor
    }
    match :name, /%1NAME=(.*)/, proc{|m|
        self.projector_name = m[1].chomp 
    }

	end

	requests do
           send :power, "#{@_digest}%1POWR ?\r", 1
           send :source, "#{@_digest}%1INPT ?\r", 1
           send :mute, "#{@_digest}%1AVMT ?\r", 1
           #send :lamp_usage, "*ltim=?#", 0.1
           send :err_status, "#{@_digest}%1ERST ?\r", 0.1
           send :lamp_usage, "#{@_digest}%1LAMP ?\r", 0.1
           send :info, "#{@_digest}%1NAME ?\r", 0.01
	end

end
