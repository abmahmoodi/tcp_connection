require 'active_record'
require 'pg'
require_relative 'jalali_date'

class Device < ActiveRecord::Base
	has_many :sensors, dependent: :destroy
end
class Sensor < ActiveRecord::Base
	belongs_to :device
end
class Temperature < ActiveRecord::Base
end

class DeviceManager
  SEN_COUNT = 4

  def initialize(device)
    @device = device
  end

  # Create a standard date and save
  def create_standard_date(adate)
    @date_time = adate.split
    @date = @date_time[0].split('/')

    @year = ('13' + @date[0]).to_i
    @month = @date[1].to_i
    @day = @date[2].to_i
    device.last_connect = JalaliDate.to_gregorian(@year, @month, @day).to_date.to_s + ' ' + @date_time[1]
    date1 = DateTime.parse(JalaliDate.to_gregorian(@year, @month, @day).to_date.to_s + ' ' + @date_time[1] + '+03:30')
    date1.in_time_zone('Tehran')
  end

  # Get online temp and find sensor to save online temp
  def online_process(online_data)
    @data = online_data.split(',')
    device.lid = @data[6].upcase
    @sensors = Sensor.where(device_id: device.id)
    @bits = bit_alarm_process(@data[4])
    
    sensor_process(@sensors, @data, @bits)
  end

  def sensor_process(sensors, data, bits)
    SEN_COUNT.times do |t|
      sensor = sensors.detect { |s| s.seq_num == t + 1 }
      sensor.last_temp = data[t] if data[t] != 'DC'
      sensor.alarm_status = bits[SEN_COUNT - (t + 1)].to_i if data[t] != 'DC'
      sensors.each { |s| s.save }
    end
  end

  def replace_char(value)
    @result = ''
    return '' unless value
    
    value.each_char do |ch|
      if (ch >= '5') && (ch <= '9')
        ch = (ch.ord + 7).chr
      end
      elsif (ch >= '/') && (ch <= '4')
        ch = (ch.ord + 44).chr
      end
      @result = "#{@result}#{ch}"
    end
    @result
  end

  def text_to_data(value)
    return -100 if value.to_s[0].nil?
    
    @result = ((((value.to_s[0].ord)-60) * 60) + ((value.to_s[1].ord)-60))
    @result = @result / 10.0 - 100
    if @result > -99.9 && @result < 259.9
      @result.round(2)
    else
      -100
    end
  end

  def temp_process(data, index)
    @sensors = device.sensors
    if data.length > 55
      @temp_data = data.split(';')
      @temp_data.each_with_index do |td, i|
        save_temp(td, @sensors, index)
      end
    else
      save_temp(data, @sensors, index)
    end
  end

  def save_temp(data, sensors, index)
    @t_data = data.split(',')
    @svalue = replace_char(@t_data[2])
    @result = ''
    24.times do |i|
      @tmp_data = @svalue[i*2, 2]
      @tmp1 = text_to_data(@tmp_data)
      if @tmp1 != -100
        @temp_date = JalaliDate.to_gregorian(JalaliDate.to_jalali(Time.now).year,
          @t_data[0], @t_data[1]).to_date.to_s + ' ' + i.to_s
        @sensor_id = (sensors.detect { |s| s.seq_num == index }).id
        @temp_exist = Temperature.where(sensor_id: @sensor_id, temp_date: DateTime.parse(@temp_date))

        if @temp_exist.empty?
          @temperature = Temperature.new
          @temperature.sensor_id = @sensor_id
          @temperature.temp_date = DateTime.parse(@temp_date)
          @temperature.temp = @tmp1
          @temperature.month = @t_data[0]
          @temperature.year = JalaliDate.to_jalali(Time.now).year
          @temperature.save
        end
      end
    end
  end

  def bit_alarm_process(alarm)
    @num = alarm.to_i
    bits = @num.to_s(2)
    bits = 
      if bits.length == 3
        "0#{bits}"
      elsif bits.length == 2
        "00#{bits}"
      elsif bits.length == 1
        "000#{bits}"
      end
    bits
  end

  def create_command(sensors)
    @sen_command = ''
    sen_name = Array.new(4)
    SEN_COUNT.times do |s|
      @sensor = sensors.detect { |s| s.seq_num == s + 1 }
      if !@sensor.nil?
        sen_name[s] = @sensor.latin_name
        @sen_command = "#{@sen_command}{SetSenPara#{s}#{@sensor.reform_value},#{@sensor.min_temp},#{@sensor.max_temp},#{@sensor.min_temp_tel},#{@sensor.max_temp_tel}}"
      end
    end
    @sensor_names = sen_name.join(",")
    @command = "{SetDevPara=#{device.temp_period},#{device.buzz},#{device.connect_period},#{device.connect_delay},#{device.alarm_type},#{device.calendar_type},#{device.sensor_type}}"
    @command = "#{@command}{SetPhonenumbers=#{@phones}}{SetName=#{@sensor_names}}#{@sensor1_command}#{@sensor2_command}#{@sensor3_command}#{@sensor4_command}"
    @command
  end

  #creat setting to send to device
  def create_setting
    @phones = Phone.select('phone').where(device_id: device.id).map{|p| [p.phone]}
    @phones = @phones.join(",")
    @sensors = Sensor.where(device_id: device.id).all
    create_command(@sensors)
  end

  def create_device(serial)
    ActiveRecord::Base.transaction do
      begin
        save_device(serial)
      rescue => e
        raise ActiveRecord::Rollback
      end
    end
  end

  def save_sensors(device_id)
    @sensor = Sensor.new
    @sensor.device_id = device_id
    @sensor.latin_name = 'Sensor' + (i + 1).to_s
    @sensor.name = 'سنسور' + (i + 1).to_s
    @sensor.reform_value = 0
    @sensor.min_temp = -50
    @sensor.max_temp = 100
    @sensor.min_temp_tel = -50
    @sensor.max_temp_tel = 100
    @sensor.seq_num = i + 1
    @sensor.sensor_type = 'T'
    @sensor.save
  end

  def save_device(serial)
    @device = Device.new
    @device.serial = serial
    @device.sensor_num = 3
    #default Value
    @device.name = ''
    @device.display_period = 1
    @device.temp_period = 7
    @device.buzz = 0
    @device.connect_period = 10
    @device.connect_delay = 1 + Random.rand(59)
    @device.alarm_type = 3
    @device.calendar_type = 0
    @device.sensor_type = 0
    if @device.save
      @device.sensor_num.times do |i|
        save_sensors(@device.id)
      end
    end
  end
end
