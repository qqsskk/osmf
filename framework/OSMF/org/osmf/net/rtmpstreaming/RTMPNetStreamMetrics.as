/*****************************************************
*  
*  Copyright 2009 Akamai Technologies, Inc.  All Rights Reserved.
*  
*****************************************************
*  The contents of this file are subject to the Mozilla Public License
*  Version 1.1 (the "License"); you may not use this file except in
*  compliance with the License. You may obtain a copy of the License at
*  http://www.mozilla.org/MPL/
*   
*  Software distributed under the License is distributed on an "AS IS"
*  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
*  License for the specific language governing rights and limitations
*  under the License.
*   
*  
*  The Initial Developer of the Original Code is Adobe Systems Incorporated.
*  Portions created by Adobe Systems Incorporated are Copyright (C) 2009 Adobe Systems 
*  Incorporated. All Rights Reserved.
* 
*****************************************************/
package org.osmf.net.rtmpstreaming
{
	import flash.events.NetStatusEvent;
	import flash.events.TimerEvent;
	import flash.net.NetStream;
	import flash.utils.Timer;
	
	import org.osmf.net.NetStreamCodes;
	import org.osmf.net.NetStreamMetricsBase;
	import org.osmf.net.StreamType;
	
	CONFIG::LOGGING
	{
	import org.osmf.logging.ILogger;
	import org.osmf.logging.Log;
	}
	
	/**
	 * The RTMPNetStreamMetrics makes use of the metrics offered by NetStream.info,
	 * but more importantly it calculates running averages, which we feel are more
	 * robust metrics on which to make switching decisions. It's goal is to be the
	 * one-stop shop for all the info you need about the health of the stream.
	 *  
	 *  @langversion 3.0
	 *  @playerversion Flash 10
	 *  @playerversion AIR 1.5
	 *  @productversion OSMF 1.0
	 */
	public class RTMPNetStreamMetrics extends NetStreamMetricsBase
	{
		/**
		 * Constructor.
		 * 
		 * @param netStream The NetStream to provide metrics for.
		 **/
		public function RTMPNetStreamMetrics(netStream:NetStream)
		{
			super(netStream);
			
			_droppedFPS = 0;
			_lastFrameDropCounter = 0;
			_lastFrameDropValue = 0;
			_maxFPS = 0;
			_averageMaxBytesPerSecondArray = new Array();
			_averageDroppedFPSArray = new Array();
			
			netStream.addEventListener(NetStatusEvent.NET_STATUS, netStatus);

			_timer = new Timer(DEFAULT_UPDATE_INTERVAL);
			_timer.addEventListener(TimerEvent.TIMER, update);
		}
		
		/**
		 * The update interval (in milliseconds) at which metrics are recalculated.
		 *  
		 *  @langversion 3.0
		 *  @playerversion Flash 10
		 *  @playerversion AIR 1.5
		 *  @productversion OSMF 1.0
		 */
		public function get updateInterval():Number 
		{
			return _timer.delay;
		}
		
		public function set updateInterval(value:Number):void 
		{
			_timer.delay = value;
		}
				
		/**
		 * The maximum achieved frame rate for this NetStream. 
		 *  
		 *  @langversion 3.0
		 *  @playerversion Flash 10
		 *  @playerversion AIR 1.5
		 *  @productversion OSMF 1.0
		 */
		public function get maxFPS():Number
		{
			return _maxFPS;
		}
		
		/**
		 * The frame drop rate calculated over the last interval.
		 *  
		 *  @langversion 3.0
		 *  @playerversion Flash 10
		 *  @playerversion AIR 1.5
		 *  @productversion OSMF 1.0
		 */
		public function get droppedFPS():Number
		{
			return _droppedFPS;
		}
		
		/**
		 * The average frame-drop rate calculated over the life of the NetStream.
		 *  
		 *  @langversion 3.0
		 *  @playerversion Flash 10
		 *  @playerversion AIR 1.5
		 *  @productversion OSMF 1.0
		 */
		public function get averageDroppedFPS():Number
		{
			return _averageDroppedFPS;
		}
		
		
		/**
		 * The average max bytes per second value, calculated based on a
		 * recent set of samples.
		 *  
		 *  @langversion 3.0
		 *  @playerversion Flash 10
		 *  @playerversion AIR 1.5
		 *  @productversion OSMF 1.0
		 */
		public function get averageMaxBytesPerSecond():Number
		{
			return _averageMaxBytesPerSecond;
		}

		// Internals
		//
		
		private function netStatus(e:NetStatusEvent):void 
		{
			switch (e.info.code) 
			{
				case NetStreamCodes.NETSTREAM_PLAY_START:
					if (!_timer.running) 
					{
						_timer.start();
					}
					break;
				case NetStreamCodes.NETSTREAM_PLAY_STOP:
					_timer.stop();
					break;
			}
		}
		
		private function update(e:TimerEvent):void 
		{
			try 
			{
				if (isNaN(netStream.time))
				{
					this._timer.stop();
					return;
				}
			
				// Average maxBytesPerSecond
				var maxBytesPerSecond:Number = netStream.info.maxBytesPerSecond;
				_averageMaxBytesPerSecondArray.unshift(maxBytesPerSecond);
				if (_averageMaxBytesPerSecondArray.length > DEFAULT_AVG_MAX_BYTES_SAMPLE_SIZE) 
				{
					_averageMaxBytesPerSecondArray.pop();
				}
				var totalMaxBytesPerSecond:Number = 0;
				var peakMaxBytesPerSecond:Number = 0;
				
				for (var b:uint = 0; b < _averageMaxBytesPerSecondArray.length; b++) 
				{
					totalMaxBytesPerSecond += _averageMaxBytesPerSecondArray[b];
					peakMaxBytesPerSecond = _averageMaxBytesPerSecondArray[b] > peakMaxBytesPerSecond ? _averageMaxBytesPerSecondArray[b]: peakMaxBytesPerSecond;
				}
				
		 		// Flash player can have problems attempting to accurately estimate 
		 		// max bytes available with live streams. The server will buffer the 
		 		// content and then dump it quickly to the client. The client sees
		 		// this as an oscillating series of maxBytesPerSecond measurements,
		 		// where the peak roughly corresponds to the true estimate of max
		 		// bandwidth available.  When isLive is true, we optimize the estimated
		 		// averageMaxBytesPerSecond. 
				_averageMaxBytesPerSecond = _averageMaxBytesPerSecondArray.length < DEFAULT_AVG_MAX_BYTES_SAMPLE_SIZE ? 0 : isLive ? peakMaxBytesPerSecond : totalMaxBytesPerSecond / _averageMaxBytesPerSecondArray.length;
				
				// Estimate max (true) framerate
				_maxFPS = netStream.currentFPS > _maxFPS ? netStream.currentFPS : _maxFPS;
				
				// Frame drop rate, per second, calculated over last second.
				if (_timer.currentCount - _lastFrameDropCounter > 1000 / _timer.delay) 
				{
					_droppedFPS = (netStream.info.droppedFrames - _lastFrameDropValue) / ((_timer.currentCount - _lastFrameDropCounter) * _timer.delay/1000);
					_lastFrameDropCounter = _timer.currentCount;
					_lastFrameDropValue = netStream.info.droppedFrames;
				}
				_averageDroppedFPSArray.unshift(_droppedFPS);
				if (_averageDroppedFPSArray.length > DEFAULT_AVG_FRAMERATE_SAMPLE_SIZE) 
				{
					_averageDroppedFPSArray.pop();
				}
				var totalDroppedFrameRate:Number = 0;
				for (var f:uint=0;f < _averageDroppedFPSArray.length;f++) 
				{
					totalDroppedFrameRate += _averageDroppedFPSArray[f];
				}
				
				_averageDroppedFPS = _averageDroppedFPSArray.length < DEFAULT_AVG_FRAMERATE_SAMPLE_SIZE ? 0 : totalDroppedFrameRate / _averageDroppedFPSArray.length;
				
			}
			catch (e:Error) 
			{
				CONFIG::LOGGING
				{
					logger.debug(".update() - " + e);
				}
				throw(e);	
			}
			
		}
		
		private function get isLive():Boolean
		{
			return resource.streamType == StreamType.LIVE;
		}
		
		private var _timer:Timer;
		private var _averageMaxBytesPerSecondArray:Array;
		private var _averageMaxBytesPerSecond:Number;
		private var _averageDroppedFPSArray:Array;
		private var _averageDroppedFPS:Number;
		private var _droppedFPS:Number;
		private var _lastFrameDropValue:Number;
		private var _lastFrameDropCounter:Number;
		private var _maxFPS:Number;
		
		private const DEFAULT_UPDATE_INTERVAL:Number = 100;
		private const DEFAULT_AVG_MAX_BYTES_SAMPLE_SIZE:Number = 50;
		private const DEFAULT_AVG_FRAMERATE_SAMPLE_SIZE:Number = 50;		
		
		CONFIG::LOGGING
		{
			private static var logger:ILogger = Log.getLogger("org.osmf.net.RTMPNetStreamMetrics");
		}
	}
}