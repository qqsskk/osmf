/*****************************************************
*  
*  Copyright 2009 Adobe Systems Incorporated.  All Rights Reserved.
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
package org.osmf.net.httpstreaming
{
	import __AS3__.vec.Vector;
	
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.NetStatusEvent;
	import flash.events.ProgressEvent;
	import flash.events.SecurityErrorEvent;
	import flash.events.TimerEvent;
	import flash.net.NetConnection;
	import flash.net.NetStream;
	import flash.net.NetStreamPlayOptions;
	import flash.net.URLLoaderDataFormat;
	import flash.net.URLStream;
	import flash.utils.ByteArray;
	import flash.utils.IDataInput;
	import flash.utils.Timer;
	
	import org.osmf.events.HTTPStreamingFileHandlerEvent;
	import org.osmf.events.HTTPStreamingIndexHandlerEvent;
	import org.osmf.net.NetClient;
	import org.osmf.net.NetStreamCodes;
	import org.osmf.net.httpstreaming.flv.FLVHeader;
	import org.osmf.net.httpstreaming.flv.FLVParser;
	import org.osmf.net.httpstreaming.flv.FLVTag;
	import org.osmf.net.httpstreaming.flv.FLVTagScriptDataObject;
	import org.osmf.net.httpstreaming.flv.FLVTagVideo;

	CONFIG::LOGGING 
	{	
		import org.osmf.logging.ILogger;
	}

	CONFIG::FLASH_10_1	
	{
		import flash.net.NetStreamAppendBytesAction;
	}
	
	[ExcludeClass]

	/**
	 * 
	 * @private
	 * 
	 * HTTPNetStream is a NetStream subclass which can accept input via the
	 * appendBytes method.  In general, the assumption is that a large media
	 * file is broken up into a number of smaller fragments.
	 * 
	 * There are two important aspects of working with an HTTPNetStream:
	 * 1) How to map a specific playback time to the media file fragment
	 * which holds the media for that time.
	 * 2) How to unmarshal the data from a media file fragment so that it can
	 * be fed to the NetStream as TCMessages. 
	 * 
	 * The former is the responsibility of HTTPStreamingIndexHandlerBase,
	 * the latter the responsibility of HTTPStreamingFileHandlerBase.
	 */	
	public class HTTPNetStream extends NetStream 
	{
		/**
		 * Constructor.
		 * 
		 * @param connection The NetConnection to use.
		 * @param indexHandler Object which exposes the index, which maps
		 * playback times to media file fragments.
		 * @param fileHandler Object which canunmarshal the data from a
		 * media file fragment so that it can be fed to the NetStream as
		 * TCMessages.
		 */
		public function HTTPNetStream
			( connection:NetConnection
			, indexHandler:HTTPStreamingIndexHandlerBase
			, fileHandler:HTTPStreamingFileHandlerBase
			)
		{
			super(connection);
			
			_savedBytes = new ByteArray();
			
			this.indexHandler = indexHandler;
			this.fileHandler = fileHandler;
			
			indexHandler.addEventListener(HTTPStreamingIndexHandlerEvent.NOTIFY_INDEX_READY, onIndexReady);
			indexHandler.addEventListener(HTTPStreamingIndexHandlerEvent.NOTIFY_RATES, onRates);
			indexHandler.addEventListener(HTTPStreamingIndexHandlerEvent.NOTIFY_TOTAL_DURATION, onTotalDuration);
			indexHandler.addEventListener(HTTPStreamingIndexHandlerEvent.REQUEST_LOAD_INDEX, onRequestLoadIndexFile);
			indexHandler.addEventListener(HTTPStreamingIndexHandlerEvent.NOTIFY_ERROR, onIndexError);
			indexHandler.addEventListener(HTTPStreamingIndexHandlerEvent.NOTIFY_ADDITIONAL_HEADER, onAdditionalHeader);
			
			fileHandler.addEventListener(HTTPStreamingFileHandlerEvent.NOTIFY_TIME_BIAS, onTimeBias);
			fileHandler.addEventListener(HTTPStreamingFileHandlerEvent.NOTIFY_SEGMENT_DURATION, onSegmentDuration);
			
			mainTimer = new Timer(MAIN_TIMER_INTERVAL); 
			mainTimer.addEventListener(TimerEvent.TIMER, onMainTimer);	
			mainTimer.start();
			
			addEventListener(NetStatusEvent.NET_STATUS, onNetStatusEvent);
			
			// Just like DynamicStream... we need to use onPlayStatus.  This is part of remapping code.
			_ownerClientObject = new Object();
			_ownerClientObject.onPlayStatus = function(... rest):void {};
			
			_trampolineObject = new NetClient();
			_trampolineObject.addHandler("onPlayStatus", onPlayStatusHS);
			super.client = _trampolineObject;
		}
		
		/**
		 * Whether HTTPNetStream implements enhanced seek on the client side.
		 * 
		 * Enhanced seek allows for keyframe-accurate seeking.
		 */
		public function set enhancedSeek(value:Boolean):void
		{
			_enhancedSeekEnabled = value;
		}
		
		public function get enhancedSeek():Boolean
		{
			return _enhancedSeekEnabled;
		}
		
		/**
		 * Getters/(setters if applicable) of a bunch of properties related to the quality of service.
		 */
		public function get downloadRatio():Number
		{
			return _lastDownloadRatio;
		}
		
		public function set qualityLevel(value:int):void
		{
			if (_manualSwitchMode)
			{
				setQualityLevel(value);
			}
			else
			{
				throw new Error("qualityLevel cannot be set to this value at this time");
			}
		}
				
		public function get qualityLevel():int
		{
			return _qualityLevel;
		}

		public function get manualSwitchMode():Boolean
		{	
			return _manualSwitchMode;
		}
		
		public function set manualSwitchMode(value:Boolean):void
		{	
			_manualSwitchMode = value;
		}
		
		// Overrides
		//
		
		/**
		 * The arguments to this method can mirror the arguments to the
		 * superclass's method:
		 * 1) media file
		 * 2) URL
		 * 3) name/start/len/reset
		 *		a) Subclips
		 *		b) Live
		 *		c) Resetting playlist
		 * 
		 * In all cases, the first param MUST be of type HTTPStreamingIndexInfoBase.
		 * The index info object will be passed to the HTTPStreamingIndexHandler.
		 * 
		 * @inheritDoc
		 */
		override public function play(...args):void 
		{
			if (args.length != 1 ||
				!(args[0] is HTTPStreamingIndexInfoBase))
			{
				throw new Error("HTTPStream.play() requires a single argument of type HTTPStreamingIndexInfoBase");
			}
						
			// Signal to the base class that we're entering Data Generation Mode.
			super.play(null);
			
			// Playback is considered to start when we first append some bytes.
			dispatchEvent
				( new NetStatusEvent
					( NetStatusEvent.NET_STATUS
					, false
					, false
					, {code:NetStreamCodes.NETSTREAM_PLAY_START, level:"status"}
					)
				); 
			
			// TODO: Add subclip and live support here.
			
			// Before we feed any TCMessages to the Flash Player, we must feed
			// an FLV header first.
			//
			
			var header:FLVHeader = new FLVHeader();
			var headerBytes:ByteArray = new ByteArray();
			header.write(headerBytes);
			attemptAppendBytes(headerBytes);
			
			// Initialize ourselves and the index handler.
			//
			
			setState(HTTPStreamingState.INIT);
						
			indexIsReady = false;
			indexHandler.initialize(args[0] as HTTPStreamingIndexInfoBase);
		
			// This is the start of playback, so no seek.
			_seekTarget = 0;
			_timeBias = _seekTarget;
		}
		
		/**
		 * @private
		 */
		override public function play2(param:NetStreamPlayOptions):void
		{
			super.play2(param);
			
			// TODO: Add support for MBR here.  Playlist support is probably
			// irrelevant for now.
		} 
		
		/**
		 * @private
		 **/
		override public function seek(offset:Number):void
		{
			// (change to override seek rather than do this based on seek notify event)
			//  can't do this unless you're already playing (for instance, you can't leave INIT to go to SEEK)! 
			// XXX need to double-check to see if there's more guards needed here
					
			if (_state != HTTPStreamingState.INIT)
			{
				_seekTarget = offset;
				setState(HTTPStreamingState.SEEK);		
				super.seek(offset);
			}
		}
		
		/**
		 * @private
		 **/
		override public function close():void
		{
			switch (_state)
			{
				case HTTPStreamingState.PLAY:
				case HTTPStreamingState.PLAY_START_NEXT:
				case HTTPStreamingState.PLAY_START_SEEK:
					_urlStreamVideo.close();	// immediate abort
			}
			setState(HTTPStreamingState.STOP);
			
			mainTimer.stop();
			
			dispatchEvent
				( new NetStatusEvent
					( NetStatusEvent.NET_STATUS
					, false
					, false
					, {code:NetStreamCodes.NETSTREAM_PLAY_STOP, level:"status"}
					)
				); 

			// XXX might need to do other things here
			super.close();
		}
		
		/**
		 * @private
		 **/
		override public function get time():Number
		{
			return super.time + _timeBias;
		}
		
		/**
		 * @private
		 **/
		override public function set client(object:Object):void 
		{
			// and just like DS, we override the client setter to get in between for onPlayStatus (and maybe more in the future)
			var description:XML = flash.utils.describeType(object);
			
			// handle serialized types		
			if (description.@name == "org.osmf.net::NetClient")
			{
				var methodList:XMLList = description..method;
				
				// loop thru all the methods on the object, assign any that aren't reserved on NetStream already (e.g. addEventListener)
				for (var i:int; i < methodList.length(); i++)
				{
					if (!this.hasOwnProperty(methodList[i].@name)) 
					{
						if (methodList[i].@name == "onPlayStatus") 
						{
							_ownerClientObject.onPlayStatus = object.onPlayStatus;	
						} 
						else 
						{
							try 
							{
								_trampolineObject[methodList[i].@name] = object[methodList[i].@name];
							} 
							catch(e:Error) 
							{
							}
						}
					}
					
				}
				
				_trampolineObject.addHandler("onPlayStatus", onPlayStatusHS);
				
				// send remapping to the base class property
				super.client = _trampolineObject;
			}
		}	
		
		// Internal
		//
		
		private function setState(value:String):void
		{
			_prevState = _state;
			_state = value;
		}
		
		private function insertScriptDataTag(tag:FLVTagScriptDataObject):void
		{
			if (!_insertScriptDataTags)
			{
				_insertScriptDataTags = new Vector.<FLVTagScriptDataObject>();
				_flvParserISD = new FLVParser(false);
			}
			_insertScriptDataTags.push(tag);
		}
		
		private function flvTagHandlerISD(tag:FLVTag):Boolean
		{
			for (var i:int = 0; i < _insertScriptDataTags.length; i++)
			{
				var t:FLVTagScriptDataObject;
				var bytes:ByteArray;
				
				t = _insertScriptDataTags[i];
				t.timestamp = tag.timestamp;
				
				bytes = new ByteArray();
				t.write(bytes);
				attemptAppendBytes(bytes);
			}
			_insertScriptDataTags = null;	
			_isdTag = tag;	// can't append this, as we might be sending it to enhanced seek or something... holding it here is a little ugly. need a context to put it in.
			return false;   // always just parse exactly the one first thing
		}	

		private function flvTagHandlerES(tag:FLVTag):Boolean
		{
			var bytes:ByteArray;
			
			if (tag is FLVTagVideo)
			{	
				if (_enhancedSeekStartSegment)	
				{
					var _muteTag:FLVTagVideo = new FLVTagVideo();
					_muteTag.timestamp = tag.timestamp; // may get overwritten, ok
					_muteTag.codecID = FLVTagVideo(tag).codecID; // same as in use
					_muteTag.frameType = FLVTagVideo.FRAME_TYPE_INFO;
					_muteTag.infoPacketValue = FLVTagVideo.INFO_PACKET_SEEK_START;
					// and start saving, with this as the first...
					_enhancedSeekTags = new Vector.<FLVTagVideo>();
					_enhancedSeekTags.push(_muteTag);
					_enhancedSeekStartSegment = false;
				}	
				
				if (tag.timestamp >= _enhancedSeekTarget)
				{
					_enhancedSeekTarget = -1;
					_timeBias = tag.timestamp / 1000.0;
					
					var _unmuteTag:FLVTagVideo = new FLVTagVideo();
					_unmuteTag.timestamp = tag.timestamp;  // may get overwritten, ok
					_unmuteTag.codecID = (_enhancedSeekTags[0]).codecID;	// take the codec ID of the corresponding SEEK_START
					_unmuteTag.frameType = FLVTagVideo.FRAME_TYPE_INFO;
					_unmuteTag.infoPacketValue = FLVTagVideo.INFO_PACKET_SEEK_END;

					_enhancedSeekTags.push(_unmuteTag);	
					
					// twiddle and dump
				
					var i:int;
					for (i=0; i<_enhancedSeekTags.length; i++)
					{
						var vTag:FLVTagVideo;
						
						vTag = _enhancedSeekTags[i];
						//vTag.timestamp = tag.timestamp;
						if (vTag.codecID == FLVTagVideo.CODEC_ID_AVC && vTag.avcPacketType == FLVTagVideo.AVC_PACKET_TYPE_NALU)
						{
							// for H.264 we need to move the timestamp forward but the composition time offset backwards to compensate
							var adjustment:int = tag.timestamp - vTag.timestamp; // how far we are adjusting
							var compTime:int = vTag.avcCompositionTimeOffset;
							compTime = vTag.avcCompositionTimeOffset;
							compTime -= adjustment; // do the adjustment
							vTag.avcCompositionTimeOffset = compTime;	// save adjustment
							vTag.timestamp = tag.timestamp; // and adjust the timestamp forward
						}
						else
						{
							// the simple case
							vTag.timestamp = tag.timestamp;
						}
						bytes = new ByteArray();
						vTag.write(bytes);
						attemptAppendBytes(bytes);
					}
					_enhancedSeekTags = null;
					
					// and dump this one
					bytes = new ByteArray();
					tag.write(bytes);
					attemptAppendBytes(bytes);
					return false;	// immediate end of parsing (caller must dump rest, unparsed)
					
				}
				else
				{
					_enhancedSeekTags.push(tag);
				}
			} 
			return true;
		}
	
		/**
		 * All decision making code for MBR switching happens in this method.
		 */
		private function autoAdjustQuality(seeking:Boolean):void
		{
			if (!_manualSwitchMode)
			{
				if (seeking)
				{
					// if we are in auto-switch, then the default is that we go to lowest rate to fulfill seek... fastest video buffer fill that way, plus for some forward seek index
					//  strategies (patent-pending) we don't even have the data we need to upswitch until we get the low-rate data
					// however, some people want to be able to control this

					setQualityLevel(0);

					return; // to avoid indenting rest of function for the else case
				}
				// auto-adjust quality level aka bitrate at this point
			
				// XXX IMPORTANT NOTE: WE AREN'T YET SETTING BUFFER TIME UPWARDS IN NON-SEEK SITUATIONS. NEED TO DO THIS SO RUNNING DRY IS LESS PAINFUL.
					
				// we work in ratios so that we can cancel kbps out of all the equations
				//   the lastDownloadRatio is "playback time of last segment downloaded" / "amount of time it took to download that whole segment, from request to finished"
				//   the switchRatio[proposed] is "claimed rate of proposed quality" / "claimed rate of current quality"
				//
				// there are exactly four cases we need to deal with, and since I'm not an optimist, I'll start from the worst case:
				// 1. the lastDownloadRatio is <1 and < switchRatio[current-1]: Bandwidth is way down, Switch to lowest rate immediately (even if there's an intermediate that might work).
				// 2. the lastDownloadRatio is <1 but >= switchRatio[current-1]: We should be able to keep going if we go down one level, do it
				// 3. the lastDownloadRatio is >= 1 but < switchRatio[current+1] OR no available rate is higher than current: Steady state where we like to be. Don't touch any knobs.
				// 4. the lastDownloadRatio is >= 1 and > switchRatio[current+1]: We can go up to rate n where n is the highest n for which lastDownloadRatio is still > switchRatio[n]
				//                                                                (but see caution about high lastDownloadRatio caused by cached response)
				//
				// XXX note: we don't currently do this, but we can hold off loading for a bit if and only if we are in state 3 AND the lastDownloadRatio is significantly >= 1
				//           (in addition to holding off loading if bufferLength is growing too far)
				// note: there is a danger that lastDownloadRatio is absurdly high because it is reflecting cached data. If that is detected, then in case 4 the switch up
				//           should only be a single quality level upwards rather than seeking the top rate instantly... just in case even one level up is actually too high a rate in reality
				//
				// XXX this is also where we could look at dropped-frame history and drop a rate level as well, if necessary. not yet implemented.
				//
				// so on to the code...
				
				var proposedLevel:int;
				var switchRatio:Number;
				
				if (_lastDownloadRatio < 1.0)
				{
					// case 1 and 2
					
					// first check to see if we are even able to switch down
					if (qualityLevel > 0)
					{
						// we are
						proposedLevel = qualityLevel - 1;
						switchRatio = _qualityRates[proposedLevel] / _qualityRates[qualityLevel];
						if (_lastDownloadRatio < switchRatio)
						{
							setQualityLevel(0);	// case 1, switch to lowest
						}
						else
						{
							setQualityLevel(proposedLevel); // case 2, down by one
						}
					}
					// else, already at lowest level
				} // case 1&2
				else
				{
					// case 3 and 4
					
					// first check to see if we are able to switch up
					if (qualityLevel < _numQualityLevels - 1) 
					{
						proposedLevel = qualityLevel + 1;
						switchRatio = _qualityRates[proposedLevel] / _qualityRates[qualityLevel];
						if (_lastDownloadRatio < switchRatio)
						{
							// case 3, don't touch anything. we're where we like to be. (well, actually, we like to be at the highest level with bandwidth to spare, but not everyone has that)
						}
						else
						{
							// is the last download ratio suspiciously high (cached data), or has aggressive upswitch been turned off?
							if (_lastDownloadRatio > 100.0 || !_aggressiveUpswitch)	// XXX 100.0 s/b constant value
							{
								// keep proposed level of +1
							}
							else
							{
								// seek better proposed level
								while (++proposedLevel < _numQualityLevels)
								{
									switchRatio = _qualityRates[proposedLevel] / _qualityRates[qualityLevel];
									if (_lastDownloadRatio < switchRatio)
										break; // found one that's too high
								}
								--proposedLevel;
							}
							setQualityLevel(proposedLevel);
						}
					}
					// else already at highest level, can't up-switch
				} // case 3&4
			} // !manualSwitch
		}
		
		private function byteSource(input:IDataInput, numBytes:int):IDataInput
		{
			if (numBytes)
			{
			 	if (_savedBytes.bytesAvailable + input.bytesAvailable < numBytes)
			 	{
					return null;
				}
			}
			else
			{
				if (_savedBytes.bytesAvailable + input.bytesAvailable < 1)
				{
					return null;
				}
			}
			
			if (_savedBytes.bytesAvailable)
			{
				var needed:int = numBytes - _savedBytes.bytesAvailable;
				if (needed > 0)
				{
					input.readBytes(_savedBytes, _savedBytes.length, needed);
				}
				
				return _savedBytes;
			}
			
			_savedBytes.length = 0;
			
			return input;
		}
		
		private function processAndAppend(inBytes:ByteArray):uint
		{
			var bytes:ByteArray;
			var processed:uint = 0;
			
			if (!inBytes)
			{
				return 0;
			}

			// XXX it is possible to put a guard on _insertScriptDataTags testing to ensure that this is only done at start-of-segment (FLV tags are in alignment)
			// XXX right now that's not a problem because the contract is that putting them on the queue only happens when safe, but you never know how it'll be used later...
			
			if (_insertScriptDataTags)	// are we starting or midway through parsing a single tag in order to know the timestamps to put on ISD tags that need to be appended?
			{	
				inBytes.position = 0; // ensure rewould
				_flvParserISD.parse(inBytes, true, flvTagHandlerISD); // appends the ISD tags, assuming it gets one whole tag in
				
				if (_insertScriptDataTags)	// should now be nulled out if we got a whole tag and appended the vector so...
				{
					// we didn't get a whole tag in. the saved _isdTag isn't even set, and there's not enough in the parser to dump forwards
					return processed;	// 0
				}
				else
				{
					bytes = new ByteArray();
					_isdTag.write(bytes);		// write back out the one tag we had to parse in order to get the timestamp
					_flvParserISD.flush(bytes);	// and flush the rest of the parser into the bytes that go downstream here
					_flvParserISD = null; // done with that
				}
			}
			else
			{
				bytes = inBytes;
			}

			// now, 'bytes' is either what came in or what we massaged above in order to appendBytes some script data objects first...
				
			if (_enhancedSeekTarget >= 0) 
			{
				bytes.position = 0; // parser works on IDataInput, ensure the array is rewound
				_flvParserES.parse(bytes, true, flvTagHandlerES); //  doesn't count towards progress, but that's ok because we are in ES mode
				if (_enhancedSeekTarget < 0)
				{
					
					// dump the rest time
					var remainingBytes:ByteArray = new ByteArray();
					_flvParserES.flush(remainingBytes);
					_flvParserES = null;
					processed += remainingBytes.length;
					attemptAppendBytes(remainingBytes);
				}
			}
			else
			{
				processed += bytes.length;
				attemptAppendBytes(bytes);
			}
			
			return processed;
		}
		
		private function onMainTimer(timerEvent:TimerEvent):void
		{	
			var bytes:ByteArray;
			
			CONFIG::LOGGING
			{
				if (_state != previouslyLoggedState)
				{
					logger.debug("State = " + _state);
					previouslyLoggedState = _state;
				}
			}

			switch (_state)
			{
				case HTTPStreamingState.INIT:
					// do nothing, but not an error to be here. could make timer run slower if we wanted.
					_seekAfterInit = true;
					break;
					
			
				// SEEK case
			
				case HTTPStreamingState.SEEK:
					switch (_prevState)
					{
						case HTTPStreamingState.PLAY:
						case HTTPStreamingState.PLAY_START_NEXT:
						case HTTPStreamingState.PLAY_START_SEEK:
							_urlStreamVideo.close();	// immediate abort
							break;
						default:
							// already not open
							break;
					}
					
					_dataAvailable = false;
					_savedBytes.length = 0;		// correct? XXX
					
					if (_enhancedSeekEnabled)
					{						
						// XXX could skip this in the case where _seekTarget * 1000 is an exact match (also note that we should pick seconds or milliseconds for the targets) XXX
						_enhancedSeekTarget = _seekTarget * 1000;
						// XXX can just reuse seek target now *and* should make ES state part of play states somehow
						// XXX there is potentially an H.264 depth issue here, where we need to do a --i to pick up enough more frames to render. must revisit.
					}
					setState(HTTPStreamingState.LOAD_SEEK);
					break;
				
				
				// LOAD cases
				case HTTPStreamingState.LOAD_WAIT:
					// XXX this delay needs to shrink proportionate to the last download ratio... when we're close to or under 1, it needs to be no delay at all
					// XXX unless the bufferLength is longer (this ties into how fast switching can happen vs. timeliness of dispatch to cover jitter in loading)
					
					// XXX for now, we have a simplistic dynamic handler, in that if downloads are going poorly, we are a bit more aggressive about prefetching
					if (this._lastDownloadRatio < 2.0)	// XXX this needs to be more linear, and/or settable
					{
						if (this.bufferLength < 7.5)	// XXX need to make settable
						{
							setState(HTTPStreamingState.LOAD_NEXT);
						}
					}
					else
					{
						if (this.bufferLength < 3.75)	// XXX need to make settable
						{
							setState(HTTPStreamingState.LOAD_NEXT);
						}					
					}
					break;
				
				case HTTPStreamingState.LOAD_NEXT:
					autoAdjustQuality(false);
					if (qualityLevelHasChanged)
					{
						bytes = fileHandler.flushFileSegment(_savedBytes.bytesAvailable ? _savedBytes : null);
						processAndAppend(bytes);
						
						// XXX for testing, putting this reporting here, but it really needs to be more informative and thus generated up in the autoAdjustQuality code
						var info:Object = new Object();
						info.code = NetStreamCodes.NETSTREAM_PLAY_TRANSITION_COMPLETE;
						info.level = "status";
						
						var sdoTag:FLVTagScriptDataObject = new FLVTagScriptDataObject();
						sdoTag.objects = ["onPlayStatus", info];
						insertScriptDataTag(sdoTag);
						
						qualityLevelHasChanged = false;
					}
					setState(HTTPStreamingState.LOAD);
					break;
					
				case HTTPStreamingState.LOAD_SEEK:
					// seek always must flush per contract
					if (!_seekAfterInit)
					{
						bytes = fileHandler.flushFileSegment(_savedBytes.bytesAvailable ? _savedBytes : null);
						// processAndAppend(bytes);	// XXX this might be unneccessary as we are about to RESET
					}
					CONFIG::FLASH_10_1
					{
						appendBytesAction(NetStreamAppendBytesAction.RESET_SEEK);
					}
					
					if (!_seekAfterInit)
					{
						autoAdjustQuality(true);
					}
						
					_seekAfterInit = false;
					setState(HTTPStreamingState.LOAD);
					break;
					
				case HTTPStreamingState.LOAD:
					
					var nextRequest:HTTPStreamRequest;
			
					// XXX the double test of _prevState in here is a little weird... might want to factor differently
					
					switch (_prevState)
					{
						case HTTPStreamingState.LOAD_SEEK:
							nextRequest = indexHandler.getFileForTime(_seekTarget, qualityLevel);
							break;
						case HTTPStreamingState.LOAD_NEXT:
							nextRequest = indexHandler.getNextFile(qualityLevel);
							break;
						default:
							throw new Error("in HTTPStreamState.LOAD with unknown _prevState " + _prevState);
							break;
					}
					
					if (nextRequest != null && nextRequest.urlRequest != null)
					{
						_loadComplete = false;	
						_urlStreamVideo.load(nextRequest.urlRequest);
						
						var date:Date = new Date();
						_lastDownloadStartTime = date.getTime();
			
						switch (_prevState)
						{
							case HTTPStreamingState.LOAD_SEEK:
								setState(HTTPStreamingState.PLAY_START_SEEK);
								break;
							case HTTPStreamingState.LOAD_NEXT:
								setState(HTTPStreamingState.PLAY_START_NEXT);
								break;
							default:
								throw new Error("in HTTPStreamState.LOAD(2) with unknown _prevState " + _prevState);
								break;
						}
					}
					else
					{
						bufferEmptyEventReceived = false;
						
						dispatchEvent
							( new NetStatusEvent
								( NetStatusEvent.NET_STATUS
								, false
								, false
								, {code:NetStreamCodes.NETSTREAM_PLAY_STOP, level:"status"}
								)
							); 

						setState(HTTPStreamingState.STOP_WAIT);
					}
					
					break;
				
				case HTTPStreamingState.STOP_WAIT:
					
					CONFIG::LOGGING
					{
						logger.debug("bufferLength = " + bufferLength);
					}
					
					// Wait until the buffer is empty before signalling stop.
					if (bufferEmptyEventReceived == true)
					{
						// XXX need to append EOS in this case for sure, even if we don't do it for some of the seek-paused cases
						// (need to update playerglobal.swc to pick that up and switch to latest build in order to have the action)
						setState(HTTPStreamingState.STOP);
						
						// Trigger the Play.Complete event through onPlayStatus
						// (to mirror what NetStream does for RTMP streams).
						client.onPlayStatus({code:NetStreamCodes.NETSTREAM_PLAY_COMPLETE});
						
						bufferEmptyEventReceived = false;
					}
					
					break;
				
				case HTTPStreamingState.PLAY_START_NEXT:

					fileHandler.beginProcessFile(false, 0);
					setState(HTTPStreamingState.PLAY);
					
					if (_enhancedSeekTarget >= 0)	// XXX REFACTOR ME
					{
						_flvParserES = new FLVParser(false);
						_enhancedSeekStartSegment = true;
					}
					break;
					
				case HTTPStreamingState.PLAY_START_SEEK:		

					fileHandler.beginProcessFile(true, _seekTarget);
					setState(HTTPStreamingState.PLAY);
					
					if (_enhancedSeekTarget >= 0)	// XXX REFACTOR ME
					{
						_flvParserES = new FLVParser(false);
						_enhancedSeekStartSegment = true;
					}
					break;		
				
							
				case HTTPStreamingState.PLAY:

					var endSegment:Boolean = false;
					
					if (_dataAvailable)
					{
						var processLimit:int = 65000*4;	// XXX needs to be settable
						var processed:int = 0;
													
						if (_enhancedSeekTarget >= 0)
						{
							processLimit = 0;	// override slow-load
						}
						
						/*
						if(_bytesAvailable < fetchBytes)
						{
							// in the past, we simply returned in this case, figuring it was cheaper to just wait for enough to accumulate
							// we might want to revisit after performance testing
							fetchBytes = _bytesAvailable;
						}
						*/
						
						var input:IDataInput = null;
						_dataAvailable = false;
						while ((input = byteSource(_urlStreamVideo, fileHandler.inputBytesNeeded)))
						{
							bytes = fileHandler.processFileSegment(input);
		
							// XXX need to deal with end of file issues
							processed += processAndAppend(bytes);
							
							if (processLimit > 0 && processed >= processLimit)
							{
								_dataAvailable = true;
								break;
							}
						}
						
						// XXX if the reason we bailed is that we didn't have enough bytes, then if loadComplete we need to consume the rest into our save buffer
						// OR, if we don't do cross-segment saving then we simply need to ensure that we don't return but simply fall through to a later case
						// for now, we do the latter (also see below)
						if (_loadComplete && !input)
						{
							endSegment = true;
						}
					}
					else
					{
						if (_loadComplete)
						{
							endSegment = true;
						}
					}
					
					if (endSegment)
					{
						// then save any leftovers for the next segment round. if this is a kind of filehandler that needs that, they won't suck dry in onEndSegment.
						if (_urlStreamVideo.bytesAvailable)
						{
							_urlStreamVideo.readBytes(_savedBytes);
						}
						else
						{
							_savedBytes.length = 0; // just to be sure
						}
																	
						setState(HTTPStreamingState.END_SEGMENT);
					}
					
					break;
				
				case HTTPStreamingState.END_SEGMENT:
					// give fileHandler a crack at any remaining data 

					bytes = fileHandler.endProcessFile(_savedBytes.bytesAvailable ? _savedBytes : null);
					processAndAppend(bytes);
					_lastDownloadRatio = _segmentDuration / _lastDownloadDuration;	// urlcomplete would have fired by now, otherwise we couldn't be done, and onEndSegment is the last possible chance to report duration

					setState(HTTPStreamingState.LOAD_WAIT);
					break;

				case HTTPStreamingState.STOP:
					// do nothing. timer could run slower in this state.
					break;

				default:
					throw new Error("HTTPStream cannot run undefined _state "+_state);
					break;
			}
		}
		
		private function onNetStatusEvent(netStatusEvent:NetStatusEvent):void
		{
			if (netStatusEvent.info.code == NetStreamCodes.NETSTREAM_BUFFER_EMPTY)
			{
				bufferEmptyEventReceived = true;
			}
		}
		
		private function onPlayStatusHS(info:Object):void
		{ 
			// just like DS, call back the owner's onPlayStatus
			_ownerClientObject.onPlayStatus(info);
		}
		
		private function onURLStatus(progressEvent:ProgressEvent):void
		{
			_dataAvailable = true;
		}
		
		private function onURLComplete(event:Event):void
		{
			var date:Date = new Date;
			
			_lastDownloadDuration = (date.getTime() - _lastDownloadStartTime) / 1000.0;
			_loadComplete = true;
		}

		private function onIndexLoadComplete(event:Event):void
		{
			// TODO: Do we even need URLLoaderWithContext anymore?
			var urlLoader:URLLoaderWithContext = URLLoaderWithContext(event.target);
			
			indexHandler.processIndexData(urlLoader.data);
		}
		
		private function onRequestLoadIndexFile(event:HTTPStreamingIndexHandlerEvent):void
		{
			var urlLoader:URLLoaderWithContext;
			
			urlLoader = new URLLoaderWithContext(event.request, null);
			if (event.binaryData)
			{
				urlLoader.dataFormat = URLLoaderDataFormat.BINARY;
			}
			else
			{
				urlLoader.dataFormat = URLLoaderDataFormat.TEXT;
			}
			
			urlLoader.addEventListener(Event.COMPLETE, onIndexLoadComplete);
			urlLoader.addEventListener(IOErrorEvent.IO_ERROR, onURLError);
			urlLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onURLError);
		}

		private function onSegmentDuration(event:HTTPStreamingFileHandlerEvent):void
		{
			_segmentDuration = event.segmentDuration;
		}

		private function onRates(event:HTTPStreamingIndexHandlerEvent):void
		{
			_qualityRates = event.rates;
			_numQualityLevels = _qualityRates.length;
		}	

		private function onTimeBias(event:HTTPStreamingFileHandlerEvent):void
		{
			_timeBias = event.timeBias;
		}		

		private function onTotalDuration(event:HTTPStreamingIndexHandlerEvent):void
		{
			_totalDuration = event.totalDuration;
			
			var object:Object = new Object();
			object["duration"] = _totalDuration;
			if (_trampolineObject.hasOwnProperty("onMetaData"))
			{
				_trampolineObject.onMetaData(object);
			}
		}

		private function onIndexReady(event:HTTPStreamingIndexHandlerEvent):void
		{
			if (!indexIsReady)
			{
				_urlStreamVideo = new URLStream();
			
				_urlStreamVideo.addEventListener(ProgressEvent.PROGRESS, onURLStatus);	
				_urlStreamVideo.addEventListener(Event.COMPLETE, onURLComplete);
				_urlStreamVideo.addEventListener(IOErrorEvent.IO_ERROR, onURLError);
				_urlStreamVideo.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onURLError);
	
				setState(HTTPStreamingState.LOAD_SEEK);
				indexIsReady = true;
			}
		}
		
		private function onURLError(error:Event):void
		{
			// We map all URL errors to Play.StreamNotFound.
			dispatchEvent
				( new NetStatusEvent
					( NetStatusEvent.NET_STATUS
					, false
					, false
					, {code:NetStreamCodes.NETSTREAM_PLAY_STREAMNOTFOUND, level:"error"}
					)
				);
		}

		private function onAdditionalHeader(event:HTTPStreamingIndexHandlerEvent):void
		{
			var flvTag:FLVTagScriptDataObject = new FLVTagScriptDataObject();
			flvTag.data = event.additionalHeader;
			insertScriptDataTag(flvTag);
		}

		/**
		 * All errors from file index handler and file handler are passed to HTTPNetStream
		 * via MediaErrorEvent. 
		 */		
		private function onIndexError(event:HTTPStreamingIndexHandlerEvent):void
		{
			// We map all Index errors to Play.StreamNotFound.
			dispatchEvent
				( new NetStatusEvent
					( NetStatusEvent.NET_STATUS
					, false
					, false
					, {code:NetStreamCodes.NETSTREAM_PLAY_STREAMNOTFOUND, level:"error"}
					)
				);
		}
		
		private function setQualityLevel(value:int):void
		{
			if (value >= 0 && value < _numQualityLevels)
			{
				if (value != _qualityLevel)
				{
					_qualityLevel = value;
					qualityLevelHasChanged = true;

					dispatchEvent
						( new NetStatusEvent
							( NetStatusEvent.NET_STATUS
							, false
							, false
							, {code:NetStreamCodes.NETSTREAM_PLAY_TRANSITION, level:"status"}
							)
						); 
				}
			}
			else
			{
				throw new Error("qualityLevel cannot be set to this value at this time");
			}
		}

		private function attemptAppendBytes(bytes:ByteArray):void
		{
			// Do nothing if this is not an Argo player.
			CONFIG::FLASH_10_1
			{
				super.appendBytes(bytes);
			}
		}

		private static const MAIN_TIMER_INTERVAL:int = 25;
		
		private var _numQualityLevels:int = 0;
		private var _qualityRates:Array; 	
		private var _segmentDuration:Number;
		private var _urlStreamVideo:URLStream = null;
		private var _loadComplete:Boolean = false;
		private var mainTimer:Timer;
		private var _dataAvailable:Boolean = false;
		private var _qualityLevel:int = 0;
		private var qualityLevelHasChanged:Boolean = false;
		private var _seekTarget:Number = -1;
		private var _timeBias:Number = 0;
		private var _lastDownloadStartTime:Number = -1;
		private var _lastDownloadDuration:Number;
		private var _lastDownloadRatio:Number = 0;
		private var _manualSwitchMode:Boolean = true;
		private var _aggressiveUpswitch:Boolean = true;	// XXX needs a getter and setter, or to be part of a pluggable rate-setter
		private var _ownerClientObject:Object;
		private var _trampolineObject:NetClient;
		private var indexHandler:HTTPStreamingIndexHandlerBase;
		private var fileHandler:HTTPStreamingFileHandlerBase;
		private var _totalDuration:Number = -1;
		private var _flvParserES:FLVParser = null;
		private var _enhancedSeekTarget:Number = -1;
		private var _enhancedSeekEnabled:Boolean = false;
		private var _enhancedSeekTags:Vector.<FLVTagVideo>;
		private var _enhancedSeekStartSegment:Boolean = false;
		private var _savedBytes:ByteArray = null;
		private var _state:String = HTTPStreamingState.INIT;
		private var _prevState:String = null;
		private var _seekAfterInit:Boolean;
		private var indexIsReady:Boolean = false;
		private var _insertScriptDataTags:Vector.<FLVTagScriptDataObject> = null;
		private var _flvParserISD:FLVParser = null;
		private var _isdTag:FLVTag = null;	// using a member var like this is a little ugly
		private var bufferEmptyEventReceived:Boolean = false;
		
		CONFIG::LOGGING
		{
			private static const logger:org.osmf.logging.ILogger = org.osmf.logging.Log.getLogger("org.osmf.net.httpstreaming.HTTPNetStream");
			
			private var previouslyLoggedState:String;
		}
	}
}