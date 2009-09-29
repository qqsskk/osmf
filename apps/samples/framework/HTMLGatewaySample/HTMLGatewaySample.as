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
package 
{
	import org.openvideoplayer.composition.ParallelElement;
	import org.openvideoplayer.composition.SerialElement;
	import org.openvideoplayer.gateways.HTMLGateway;
	import org.openvideoplayer.gateways.RegionSprite;
	import org.openvideoplayer.html.HTMLElement;
	import org.openvideoplayer.media.MediaPlayer;
	import org.openvideoplayer.media.URLResource;
	import org.openvideoplayer.net.NetLoader;
	import org.openvideoplayer.utils.URL;
	import org.openvideoplayer.video.VideoElement;

	[SWF(backgroundColor='#333333', frameRate='30', width='640', height='358')]
	public class HTMLGatewaySample extends RegionSprite
	{
		public function HTMLGatewaySample()
		{
			var htmlGateway:HTMLGateway = new HTMLGateway();
			htmlGateway.initialize("bannerGateway");
			
			var rootElement:ParallelElement = new ParallelElement();
			
				var banners:SerialElement = new SerialElement();
				rootElement.addChild(banners);
				
					var banner1:HTMLElement = new HTMLElement();
					banner1.resource = new URLResource(new URL(BANNER_1));
					banner1.gateway = htmlGateway;
					banners.addChild(banner1);
					
					var banner2:HTMLElement = new HTMLElement();
					banner2.resource = new URLResource(new URL(BANNER_2));
					banner2.gateway = htmlGateway;
					banners.addChild(banner2);
					
					var banner3:HTMLElement = new HTMLElement();
					banner3.resource = new URLResource(new URL(BANNER_3));
					banner3.gateway = htmlGateway;
					banners.addChild(banner3);
				
				var video:VideoElement = constructVideo(REMOTE_PROGRESSIVE);
				rootElement.addChild(video);
			
			this.addElement(rootElement);
			
			var mediaPlayer:MediaPlayer = new MediaPlayer();
			mediaPlayer.autoPlay = true;
			mediaPlayer.source = rootElement;
		}
		
		private function constructVideo(url:String):VideoElement
		{
			return new VideoElement
					( new NetLoader
					, new URLResource(new URL(url))
					);
		}
		
		private static const REMOTE_PROGRESSIVE:String
			= "http://mediapm.edgesuite.net/strobe/content/test/AFaerysTale_sylviaApostol_640_500_short.flv";
			
		private static const BANNER_1:String
			= "http://www.iab.net/media/image/468x60.gif";
			
		private static const BANNER_2:String
			= "http://www.iab.net/media/image/234x60.gif";
			
		private static const BANNER_3:String
			= "http://www.iab.net/media/image/120x60.gif";
	}
}