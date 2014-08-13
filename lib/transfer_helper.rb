require 'active_record'
require 'pg'
require 'jalali_date'
require 'lib/device_manager'

class Device < ActiveRecord::Base
	has_many :sensors, dependent: :destroy
end
class Sensor < ActiveRecord::Base
	belongs_to :device
end
class Temperature < ActiveRecord::Base
end

class DeviceParams
	attr_accessor :uid, :date, :alarm, :etebar, :online, :data0, :data1, :data2, :data3

	def initialize(uid, date, alarm, etebar, online, data0, data1, data2, data3)
		@uid = uid
		@date = date
		@alarm = alarm
		@etebar = etebar
		@online = online
		@date0 = data0
		@date1 = data1
		@date2 = data2
		@date3 = data3
	end
end

module TransferHelper
  def self.device_init(device_params)
    # Create database connection.
    connect_to_db	
    @device = Device.where(serial: device_params.uid.to_s).first
    @device_manager = DeviceManager.new(@device)
    if @device.nil?
      @device_manager.create_device(device_params.uid)
    end
    if @device.is_changed
      @device.is_changed = false
      @setting = @device_manager.create_setting(@device)
    end
    
    @device.alarm_type = device_params.alarm
    @device.credit_value = device_params.etebar

    @device_manager.online_process(device_params.online)
    
    sensors_process(device_params)
    dif = time_difference(@device_manager, device_params.date)
    if @device.save
      return device_response(dif, @setting)
    end
  end

  def device_response(dif, setting)
  	if dif > 1 || dif < -1
  		@day_of_week = Time.now.wday + 2
      return "\"SiteMessage{SetDate=#{JalaliDate.to_jalali(Time.now.in_time_zone('Tehran')).strftime("%y,%m,%d,") +
      @day_of_week.to_s + Time.now.in_time_zone('Tehran').strftime(',%H,%M,%S')}}" +@setting.to_s+ "{OK}\""
    else
      return "\"SiteMessage" + @setting.to_s + "{OK}\""
    end
  end

  def sensors_process(device_params)
  	@device_manager.temp_process(device_params.data0, 1) if device_params.data0
    @device_manager.temp_process(device_params.data1, 2) if device_params.data1
    @device_manager.temp_process(device_params.data2, 3) if device_params.data2
    @device_manager.temp_process(device_params.data3, 4) if device_params.data3
  end

  def time_difference(device_manager, date)
  	device_date = @device_manager.create_standard_date(date)
    dif = ((device_date - Time.now.in_time_zone('Tehran')) / 3600).round(1)
    return dif
  end

	def connect_to_db
	  ActiveRecord::Base.establish_connection(:adapter => "postgresql",
      																			:username => "postgres",
																		        :password => "pass",
      																			:database => "device")
	end
end
