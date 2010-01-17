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
*  The Initial Developer of the Original Code is Akamai Technologies, Inc.
*  Portions created by Akamai Technologies, Inc. are Copyright (C) 2009 Akamai 
*  Technologies, Inc. All Rights Reserved. 
*  
*****************************************************/
package org.osmf.smil.loader
{
	import __AS3__.vec.Vector;
	
	import flash.events.ErrorEvent;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	
	import org.osmf.events.MediaError;
	import org.osmf.events.MediaErrorEvent;
	import org.osmf.media.DefaultMediaFactory;
	import org.osmf.media.MediaElement;
	import org.osmf.media.MediaFactory;
	import org.osmf.media.MediaResourceBase;
	import org.osmf.media.URLResource;
	import org.osmf.metadata.MetadataUtils;
	import org.osmf.proxies.MediaElementLoadedContext;
	import org.osmf.proxies.MediaElementLoader;
	import org.osmf.smil.media.SMILMediaGenerator;
	import org.osmf.smil.model.SMILDocument;
	import org.osmf.smil.parser.SMILParser;
	import org.osmf.traits.LoadState;
	import org.osmf.traits.LoadTrait;

	/**
	 * The SMILLoader class will load a SMIL (Synchronized 
	 * Multimedia Integration Language) file and generate
	 * a loaded context.
	 */
	public class SMILLoader extends MediaElementLoader
	{
		/**
		 * The SMIL mime type as of SMIL 3.0.
		 */
		public static const SMIL_MIME_TYPE:String = "application/smil+xml";

		/**
		 * Constructor.
		 * 
		 * @param factory The factory that is used to create MediaElements based on the
		 * media specified in the SMIL file.  A default factory is created for the base 
		 * OSMF media types: Video, Audio, Image, and SWF.
		 */		
		public function SMILLoader(mediaFactory:MediaFactory = null)
		{
			super();
			
			supportedMimeTypes.push(SMIL_MIME_TYPE);
			
			if (mediaFactory == null)
			{
				factory = new DefaultMediaFactory();
			}
			else
			{
				factory = mediaFactory;			
			}
		}

		/**
		 * @private
		 */ 
		override public function canHandleResource(resource:MediaResourceBase):Boolean
		{	
			var match:int = MetadataUtils.checkMetadataMatchWithResource(resource, mediaTypesSupported, supportedMimeTypes);
			var canHandle:Boolean = false;
			
			if (match == MetadataUtils.METADATA_MATCH_FOUND)
			{
				canHandle = true;
			}
			else if (resource is URLResource)
			{
				var urlResource:URLResource = URLResource(resource);
				canHandle =  (urlResource.url.path.search(/\.smi$|\.smil$/i) != -1);
			}		
			
			return canHandle;
		}
		
		/**
		 * @private
		 */
		override public function load(loadTrait:LoadTrait):void
		{
			super.load(loadTrait);
			updateLoadTrait(loadTrait, LoadState.LOADING);

			var urlLoader:URLLoader = new URLLoader(new URLRequest(URLResource(loadTrait.resource).url.rawUrl));
			setupListeners();
			
			function setupListeners(add:Boolean=true):void
			{
				if (add)
				{
					urlLoader.addEventListener(Event.COMPLETE, onComplete);
					urlLoader.addEventListener(IOErrorEvent.IO_ERROR, onError);
					urlLoader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);
				}
				else
				{
					urlLoader.removeEventListener(Event.COMPLETE, onComplete);
					urlLoader.removeEventListener(IOErrorEvent.IO_ERROR, onError);
					urlLoader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, onError);
				}
			}
			
			function onError(event:ErrorEvent):void
			{
				setupListeners(false);
				updateLoadTrait(loadTrait, LoadState.LOAD_ERROR); 	
				loadTrait.dispatchEvent(new MediaErrorEvent(MediaErrorEvent.MEDIA_ERROR, false, false, new MediaError(0, event.text)));
			}			

			function onComplete(event:Event):void
			{	
				setupListeners(false);
				
				try
				{
					var parser:SMILParser = createParser();
					var smilDocument:SMILDocument = parser.parse(event.target.data);
					finishLoad(loadTrait, smilDocument);
				}
				catch (parseError:Error)
				{					
					updateLoadTrait(loadTrait, LoadState.LOAD_ERROR);
					loadTrait.dispatchEvent(new MediaErrorEvent(MediaErrorEvent.MEDIA_ERROR, false, false, new MediaError(parseError.errorID, parseError.message)));
				}
			}	
		}
		
		/**
		 * @private
		 */
		override public function unload(loadTrait:LoadTrait):void
		{
			super.unload(loadTrait);	
			var context:MediaElementLoadedContext = loadTrait.loadedContext as MediaElementLoadedContext;
			updateLoadTrait(loadTrait, LoadState.UNLOADING, context);
			updateLoadTrait(loadTrait, LoadState.UNINITIALIZED, null);					
		}
		
		/**
		 * Override to provide a custom media generator.
		 */
		protected function createMediaGenerator():SMILMediaGenerator
		{
			return new SMILMediaGenerator();	
		}
		
		/**
		 * Override to provide a custom SMIL parser.
		 */
		protected function createParser():SMILParser
		{
			return new SMILParser();
		}
		
		private function finishLoad(loadTrait:LoadTrait, smilDocument:SMILDocument):void
		{
			var mediaGenerator:SMILMediaGenerator = createMediaGenerator();
			var loadedElement:MediaElement = mediaGenerator.createMediaElement(smilDocument, factory);
			
			if (loadedElement == null)
			{
				updateLoadTrait(loadTrait, LoadState.LOAD_ERROR);
			}
			else
			{
				var context:MediaElementLoadedContext = new MediaElementLoadedContext(loadedElement);
				updateLoadTrait(loadTrait, LoadState.READY, context);
			}		
		}
				
		private var supportedMimeTypes:Vector.<String> = new Vector.<String>();
		private var mediaTypesSupported:Vector.<String> = new Vector.<String>();
		private var factory:MediaFactory;
	}
}