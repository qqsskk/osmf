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
package org.osmf.video
{
	import flash.events.Event;
	
	import org.osmf.events.LoadEvent;
	import org.osmf.events.MediaErrorCodes;
	import org.osmf.events.MediaErrorEvent;
	import org.osmf.events.MetadataEvent;
	import org.osmf.events.ViewEvent;
	import org.osmf.media.IMediaResource;
	import org.osmf.media.MediaElement;
	import org.osmf.media.MediaPlayer;
	import org.osmf.media.TestMediaElement;
	import org.osmf.media.URLResource;
	import org.osmf.metadata.TemporalFacet;
	import org.osmf.metadata.TemporalFacetEvent;
	import org.osmf.net.NetLoader;
	import org.osmf.net.NetStreamCodes;
	import org.osmf.net.StreamType;
	import org.osmf.net.StreamingURLResource;
	import org.osmf.netmocker.EventInfo;
	import org.osmf.netmocker.MockNetLoader;
	import org.osmf.traits.LoadState;
	import org.osmf.traits.LoadTrait;
	import org.osmf.traits.MediaTraitType;
	import org.osmf.traits.PlayTrait;
	import org.osmf.traits.SeekTrait;
	import org.osmf.traits.TimeTrait;
	import org.osmf.traits.ViewTrait;
	import org.osmf.utils.NetFactory;
	import org.osmf.utils.TestConstants;
	import org.osmf.utils.URL;

	public class TestVideoElement extends TestMediaElement
	{
		override public function setUp():void
		{
			netFactory = new NetFactory();
			loader = netFactory.createNetLoader();

			super.setUp();
		}
		
		override public function tearDown():void
		{
			super.tearDown();
			
			netFactory = null;
			loader = null;
		}
		
		////////////////////////////////////////////////////////
		//
		//	Tests
		//
		////////////////////////////////////////////////////////
		
		public function testDefaultDuration():void
		{
			var element:VideoElement = new VideoElement(new NetLoader());
			assertEquals(NaN, element.defaultDuration);
			
			element.defaultDuration = 100;
			assertEquals(100, element.defaultDuration);
			
			var timeTrait:TimeTrait = element.getTrait(MediaTraitType.TIME) as TimeTrait;
			assertNotNull(timeTrait);
			assertEquals(timeTrait.duration, 100);
			
			element.defaultDuration = NaN;
			assertEquals(NaN, element.defaultDuration);
			
			timeTrait = element.getTrait(MediaTraitType.TIME) as TimeTrait;
			assertNull(timeTrait);
		}
		
		public function testGetClient():void
		{
			var videoElement:VideoElement = createMediaElement() as VideoElement;
			videoElement.resource = resourceForMediaElement;

			eventDispatcher.addEventListener("testComplete", addAsync(mustReceiveEvent, 4000));

			var loadTrait:LoadTrait= videoElement.getTrait(MediaTraitType.LOAD) as LoadTrait;
			assertTrue(loadTrait != null);
			loadTrait.addEventListener(LoadEvent.LOAD_STATE_CHANGE, onLoadStateChange);
			loadTrait.load();
			
			function onLoadStateChange(event:LoadEvent):void
			{
				if (event.loadState == LoadState.READY)
				{
					loadTrait.removeEventListener(LoadEvent.LOAD_STATE_CHANGE, onLoadStateChange);
					assertNotNull(videoElement.client);
					eventDispatcher.dispatchEvent(new Event("testComplete"));
				}
			}
		}
		
		public function testLiveTraits():void
		{
			var videoElement:VideoElement = createMediaElement() as VideoElement;
			videoElement.resource = new StreamingURLResource(new URL(TestConstants.REMOTE_STREAMING_VIDEO_LIVE),
																StreamType.LIVE);

			eventDispatcher.addEventListener("testComplete", addAsync(mustReceiveEvent, 4000));

			var loadTrait:LoadTrait = videoElement.getTrait(MediaTraitType.LOAD) as LoadTrait;
			assertTrue(loadTrait != null);
			loadTrait.addEventListener(LoadEvent.LOAD_STATE_CHANGE, onLoadStateChange);
			loadTrait.load();
			
			function onLoadStateChange(event:LoadEvent):void
			{
				if (event.loadState == LoadState.READY)
				{
					loadTrait.removeEventListener(LoadEvent.LOAD_STATE_CHANGE, onLoadStateChange);
					
					var seekTrait:SeekTrait = videoElement.getTrait(MediaTraitType.SEEK) as SeekTrait;
					assertNull(seekTrait);
					
					var playTrait:PlayTrait = videoElement.getTrait(MediaTraitType.PLAY) as PlayTrait;
					assertNotNull(playTrait);
					eventDispatcher.dispatchEvent(new Event("testComplete"));
				}
			}
		}
		
		/**
		 * This test is for the in-stream onCuePoint callback
		 * in VideoElement.
		 */
		public function testOnCuePoint():void
		{
			var cuePointCount:int = 0;
			
			if (loader is MockNetLoader)
			{
				var testCuePoints:Array = [ {type:"event", time:1, name:"1 sec"},
										{type:"event", time:2, name:"2 sec"},
										{type:"event", time:3, name:"3 sec"} ];
				cuePoints = testCuePoints;
			}
			
			var videoElement:VideoElement = createMediaElement() as VideoElement;
			videoElement.resource = new URLResource(new URL(TestConstants.REMOTE_STREAMING_VIDEO));
			videoElement.metadata.addEventListener(MetadataEvent.FACET_ADD, onFacetAdd);
			
			eventDispatcher.addEventListener("testComplete", addAsync(mustReceiveEvent, 4000));

			var loadTrait:LoadTrait = videoElement.getTrait(MediaTraitType.LOAD) as LoadTrait;
			assertTrue(loadTrait != null);
			loadTrait.addEventListener(LoadEvent.LOAD_STATE_CHANGE, onLoadStateChange);
			loadTrait.load();
			
			function onLoadStateChange(event:LoadEvent):void
			{
				if (event.loadState == LoadState.READY)
				{
					loadTrait.removeEventListener(LoadEvent.LOAD_STATE_CHANGE, onLoadStateChange);
					
					var playTrait:PlayTrait = videoElement.getTrait(MediaTraitType.PLAY) as PlayTrait;
					playTrait.play();
				}
			}

			function onFacetAdd(event:MetadataEvent):void
			{
				if (event.facet is TemporalFacet)
				{
					videoElement.metadata.removeEventListener(MetadataEvent.FACET_ADD, onFacetAdd);
					event.facet.addEventListener(TemporalFacetEvent.POSITION_REACHED, onPositionReached);
				}
			}
			
			function onPositionReached(event:TemporalFacetEvent):void
			{
				if (testCuePoints)
				{
					if (++cuePointCount >= testCuePoints.length)
					{
						eventDispatcher.dispatchEvent(new Event("testComplete"));
						cuePoints = null;				
					} 
				}
			}
		}

		public function testGetMetadata():void
		{
			var mediaElement:MediaElement = createMediaElement();
			mediaElement.resource = resourceForMediaElement;
			
			eventDispatcher.addEventListener("testComplete", addAsync(mustReceiveEvent, 4000));

			var loadTrait:LoadTrait = mediaElement.getTrait(MediaTraitType.LOAD) as LoadTrait;
			assertTrue(loadTrait != null);
			loadTrait.addEventListener
					( LoadEvent.LOAD_STATE_CHANGE
					, onTestGetMetadata
					);
			loadTrait.load();
			
			function onTestGetMetadata(event:LoadEvent):void
			{
				if (event.loadState == LoadState.READY)
				{
					loadTrait.removeEventListener(LoadEvent.LOAD_STATE_CHANGE, onTestGetMetadata);
					
					// We should now have a view trait with the default dimensions:
					var viewTrait:ViewTrait = mediaElement.getTrait(MediaTraitType.VIEW) as ViewTrait;
					assertTrue(viewTrait != null);
					assertTrue(viewTrait.mediaWidth == 0);
					assertTrue(viewTrait.mediaHeight == 0);
					
					// See if the view matches the reported size:
					assertEquals(0, viewTrait.view.width);
					assertEquals(0, viewTrait.view.height);
					
					viewTrait.addEventListener
							( ViewEvent.MEDIA_SIZE_CHANGE
							, onMediaSizeChange
							);
					
					// Playing the media should result in our receiving the
					// metadata, which should impact our dimensions.
					var playTrait:PlayTrait = mediaElement.getTrait(MediaTraitType.PLAY) as PlayTrait;
					assertTrue(playTrait != null);
					playTrait.play();
					
					function onMediaSizeChange(event:ViewEvent):void
					{
						viewTrait.removeEventListener(ViewEvent.MEDIA_SIZE_CHANGE, onMediaSizeChange);
						
						assertTrue(viewTrait.mediaWidth == TestConstants.REMOTE_PROGRESSIVE_VIDEO_EXPECTED_WIDTH);
						assertTrue(viewTrait.mediaHeight == TestConstants.REMOTE_PROGRESSIVE_VIDEO_EXPECTED_HEIGHT);
						
						assertEquals(viewTrait.mediaWidth, viewTrait.view.width);
						assertEquals(viewTrait.mediaHeight, viewTrait.view.height);
						
						eventDispatcher.dispatchEvent(new Event("testComplete"));
					}
				}
			}
		}

		public function testMediaErrorPlayFailed():void
		{
			doTestMediaError(NetStreamCodes.NETSTREAM_PLAY_FAILED, MediaErrorCodes.PLAY_FAILED);
		}

		public function testMediaErrorStreamNotFound():void
		{
			doTestMediaError(NetStreamCodes.NETSTREAM_PLAY_STREAMNOTFOUND, MediaErrorCodes.STREAM_NOT_FOUND);
		}
		
		public function testMediaErrorFileStructureInvalid():void
		{
			doTestMediaError(NetStreamCodes.NETSTREAM_PLAY_FILESTRUCTUREINVALID, MediaErrorCodes.FILE_STRUCTURE_INVALID);
		}

		public function testMediaErrorNoSupportedTrackFound():void
		{
			doTestMediaError(NetStreamCodes.NETSTREAM_PLAY_NOSUPPORTEDTRACKFOUND, MediaErrorCodes.NO_SUPPORTED_TRACK_FOUND);
		}

		////////////////////////////////////////////////////////
		//
		//	Private and Protected properties and methods
		//
		////////////////////////////////////////////////////////

		override protected function createMediaElement():MediaElement
		{
			if (loader is MockNetLoader)
			{
				// Give our mock loader an arbitrary duration and size to ensure
				// we get metadata.
				MockNetLoader(loader).netStreamExpectedDuration = TestConstants.REMOTE_PROGRESSIVE_VIDEO_EXPECTED_DURATION;
				MockNetLoader(loader).netStreamExpectedWidth = TestConstants.REMOTE_PROGRESSIVE_VIDEO_EXPECTED_WIDTH;
				MockNetLoader(loader).netStreamExpectedHeight = TestConstants.REMOTE_PROGRESSIVE_VIDEO_EXPECTED_HEIGHT;
				
				if (cuePoints != null && cuePoints.length > 0)
				{
					MockNetLoader(loader).netStreamExpectedCuePoints = cuePoints;
				}
			}

			return new VideoElement(loader); 
		}
		
		override protected function get hasLoadTrait():Boolean
		{
			return true;
		}
		
		override protected function get resourceForMediaElement():IMediaResource
		{
			// Use a valid URL so that the tests will pass if we use
			// a real NetLoader rather than a MockNetLoader.
			return new URLResource(new URL(TestConstants.REMOTE_PROGRESSIVE_VIDEO));
		}
		
		override protected function get existentTraitTypesOnInitialization():Array
		{
			return [MediaTraitType.LOAD];
		}

		override protected function get existentTraitTypesAfterLoad():Array
		{
			return [ MediaTraitType.AUDIO
				   , MediaTraitType.BUFFER
				   , MediaTraitType.LOAD
				   , MediaTraitType.PLAY
				   , MediaTraitType.SEEK
				   , MediaTraitType.TIME
				   , MediaTraitType.VIEW
				   ];
		}	

		private function doTestMediaError(netStreamCode:String, errorID:int, level:String="error"):void
		{
			var mockLoader:MockNetLoader = loader as MockNetLoader;
			if (mockLoader != null)
			{
				mockLoader.netStreamExpectedEvents = [ new EventInfo(netStreamCode, level, 0) ];
					
				var mediaElement:MediaElement = createMediaElement();
				mediaElement.resource = resourceForMediaElement;
				
				mediaElement.addEventListener(MediaErrorEvent.MEDIA_ERROR, onTestMediaError);
				
				eventDispatcher.addEventListener("testComplete", addAsync(mustReceiveEvent, 4000));
				
				var mediaPlayer:MediaPlayer = new MediaPlayer(mediaElement);
				
				function onTestMediaError(event:MediaErrorEvent):void
				{
					assertTrue(event.error.errorID == errorID);
					
					eventDispatcher.dispatchEvent(new Event("testComplete"));
				}
			}
		}
		
		private var netFactory:NetFactory;
		private var loader:NetLoader;
		private var cuePoints:Array;
	}
}
