package org.osmf.test.captioning.media
{
	import flash.events.Event;
	
	import mx.events.IndexChangedEvent;
	
	import org.osmf.captioning.CaptioningPluginInfo;
	import org.osmf.captioning.media.CaptioningProxyElement;
	import org.osmf.events.LoadEvent;
	import org.osmf.events.MediaErrorEvent;
	import org.osmf.media.IURLResource;
	import org.osmf.media.MediaElement;
	import org.osmf.media.TestMediaElement;
	import org.osmf.media.URLResource;
	import org.osmf.metadata.KeyValueFacet;
	import org.osmf.metadata.ObjectIdentifier;
	import org.osmf.net.NetLoader;
	import org.osmf.test.captioning.CaptioningTestConstants;
	import org.osmf.traits.LoadState;
	import org.osmf.traits.LoadTrait;
	import org.osmf.traits.MediaTraitType;
	import org.osmf.utils.FMSURL;
	import org.osmf.utils.URL;
	import org.osmf.video.VideoElement;
	

	public class TestCaptioningProxyElement extends TestMediaElement
	{
		public function testConstructor():void
		{
			var proxyElement:CaptioningProxyElement = new CaptioningProxyElement(new MediaElement());
			assertNotNull(proxyElement);
		}
		
		
		public function testSetWrappedElement():void
		{
			var proxyElement:CaptioningProxyElement = new CaptioningProxyElement();
			
			// Should not throw an exception
			try
			{
				proxyElement.wrappedElement = null;
			}
			catch(error:Error)
			{	
				fail();
			}
		}
		
		/**
		 * Test loading with valid metadata and tell the CaptioningProxyElement class
		 * we DO NOT want to continue the load if the captioning document load and parse
		 * fails.
		 */
		public function testLoadWithValidMetadata():void
		{
			var mediaElement:MediaElement = new VideoElement(new NetLoader());
			mediaElement.resource = createResource(CaptioningTestConstants.CAPTIONING_DOCUMENT_URL);

			eventDispatcher.addEventListener("testComplete", addAsync(mustReceiveEvent, TIMEOUT));

			var proxyElement:CaptioningProxyElement = new CaptioningProxyElement(mediaElement, false);
			var loadTrait:LoadTrait = mediaElement.getTrait(MediaTraitType.LOAD) as LoadTrait;
			loadTrait.addEventListener(LoadEvent.LOAD_STATE_CHANGE, onLoadStateChange)

			var proxyLoadTrait:LoadTrait = proxyElement.getTrait(MediaTraitType.LOAD) as LoadTrait		
			proxyLoadTrait.load();
			
			function onLoadStateChange(event:LoadEvent):void
			{
				if (event.loadState == LoadState.READY)
				{
					eventDispatcher.dispatchEvent(new Event("testComplete"));
				}
			}
		}

		/**
		 * Test loading with invalid metadata and tell the CaptioningProxyElement class
		 * we DO NOT want to continue the media element load if the captioning document load fails.
		 */
		public function testLoadWithInvalidMetadataAndDoNotContinueLoadingMedia():void
		{
			// Test with a bad url
			doLoadWithInvalidMetadataAndDoNotContinueLoadingMedia(CaptioningTestConstants.INVALID_CAPTIONING_DOCUMENT_URL);
			// Test with null url
			doLoadWithInvalidMetadataAndDoNotContinueLoadingMedia(null);
			// Test with null facet
			doLoadWithInvalidMetadataAndDoNotContinueLoadingMedia(null, true);
		}

		/**
		 * Test loading with invalid metadata and tell the CaptioningProxyElement class
		 * we DO want to continue the media element load if the captioning document load fails.
		 */
		public function testLoadWithInvalidMetadataAndContinueLoadingMedia():void
		{
			// Test with a bad url
			doLoadWithInvalidMetadataAndContinueLoadingMedia(CaptioningTestConstants.INVALID_CAPTIONING_DOCUMENT_URL);
			// Test with null url
			doLoadWithInvalidMetadataAndContinueLoadingMedia(null);
		}

		//////////////////////////////////////////////////////////
		//
		// Helper methods
		//
		//////////////////////////////////////////////////////////
		
		private function doLoadWithInvalidMetadataAndDoNotContinueLoadingMedia(metadataURL:String, nullFacet:Boolean=false):void
		{
			var mediaElement:MediaElement = new VideoElement(new NetLoader());
			
			mediaElement.resource = nullFacet ? createResourceWithBadFacet() : createResource(metadataURL);

			eventDispatcher.addEventListener("testComplete", addAsync(mustReceiveEvent, TIMEOUT));

			var proxyElement:CaptioningProxyElement = new CaptioningProxyElement(null, false);
			proxyElement.addEventListener(MediaErrorEvent.MEDIA_ERROR, onMediaError);
			proxyElement.wrappedElement = mediaElement;
						
			var loadTrait:LoadTrait = proxyElement.getTrait(MediaTraitType.LOAD) as LoadTrait;
			loadTrait.addEventListener(LoadEvent.LOAD_STATE_CHANGE, onLoadStateChange);
			loadTrait.load();
			
			function onLoadStateChange(event:LoadEvent):void
			{
				if (event.loadState == LoadState.LOAD_ERROR)
				{
					eventDispatcher.dispatchEvent(new Event("testComplete"));
				}
			}
			
			function onMediaError(event:MediaErrorEvent):void
			{
				eventDispatcher.dispatchEvent(new Event("testComplete"));
			}
		}

		private function doLoadWithInvalidMetadataAndContinueLoadingMedia(metadataURL:String):void
		{
			var mediaElement:MediaElement = new VideoElement(new NetLoader());
			mediaElement.resource = createResource(metadataURL);

			eventDispatcher.addEventListener("testComplete", addAsync(mustReceiveEvent, TIMEOUT));

			var proxyElement:CaptioningProxyElement = new CaptioningProxyElement(mediaElement, true);
			var loadTrait:LoadTrait = mediaElement.getTrait(MediaTraitType.LOAD) as LoadTrait;
			loadTrait.addEventListener(LoadEvent.LOAD_STATE_CHANGE, onLoadStateChange)

			var proxyLoadTrait:LoadTrait = proxyElement.getTrait(MediaTraitType.LOAD) as LoadTrait		
			proxyLoadTrait.load();
			
			assertTrue(proxyElement.continueLoadOnFailure);
			
			function onLoadStateChange(event:LoadEvent):void
			{
				if (event.loadState == LoadState.READY)
				{
					eventDispatcher.dispatchEvent(new Event("testComplete"));
				}
			}
		}

		private function createResource(captioningDoc:String):IURLResource
		{
			var resource:IURLResource = new URLResource(new FMSURL(REMOTE_STREAM));				
	
			var kvFacet:KeyValueFacet = new KeyValueFacet(CaptioningPluginInfo.CAPTIONING_METADATA_NAMESPACE);
			kvFacet.addValue(new ObjectIdentifier(CaptioningPluginInfo.CAPTIONING_METADATA_KEY_URI), captioningDoc);
			resource.metadata.addFacet(kvFacet);
			return resource;			
		}
		
		private function createResourceWithBadFacet():IURLResource
		{
			var resource:IURLResource = new URLResource(new FMSURL(REMOTE_STREAM));				
			var kvFacet:KeyValueFacet = new KeyValueFacet(new URL("http://www.osmf.bogus/captioning/1.0"));
			kvFacet.addValue(new ObjectIdentifier(CaptioningPluginInfo.CAPTIONING_METADATA_KEY_URI), null);
			resource.metadata.addFacet(kvFacet);
			return resource;			
		}

		private static const REMOTE_STREAM:String = "rtmp://cp67126.edgefcs.net/ondemand/mediapm/strobe/content/test/SpaceAloneHD_sounas_640_500_short";
		private static const TIMEOUT:int = 8000;
		
	}
}