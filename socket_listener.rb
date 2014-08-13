# This is to receive data save it and send response to client.

require 'rubygems'
require 'eventmachine'
require 'json'
require 'lib/transfer_helper'

class DataBuffer < EM::Protocols::LineAndTextProtocol
  def initialize
    @line_ctr = 0
    @databuf = []
  end

  # Receive data as json from client.
  def receive_data(data)
    begin
      js = JSON.parse(data)
      device_params = DeviceParams.new((js["UID"], js["Date"], js["ALARM"], 
        js["Etebar"], js["Online"], js["Data0"], js["Data1"], js["Data2"], 
        js["Data3"])
      @ret_value = TransferHelper.device_init(device_params)
      send_data(@ret_value + "\n")
      reset_databuf()
    rescue => e
      # log_error "Error: #{e.message}"
    end
  end

  private

  def reset_databuf
    @line_ctr = 0
    @databuf = []
  end
end

# Create a process and listen to tcp port: 8962
Process.daemon(true)
pid = Process.fork do
    EventMachine::run {
      EventMachine::start_server "127.0.0.1", 8962, DataBuffer
    }
end
  
