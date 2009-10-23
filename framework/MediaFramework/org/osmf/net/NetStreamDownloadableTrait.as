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
package org.osmf.net
{
	import flash.events.IEventDispatcher;
	import flash.net.NetStream;
	
	import org.osmf.traits.DownloadableTrait;

	/**
	 * This class extends Downloadable trait to provide access to the bytesLoaded and bytesTotal properties
	 * of NetStream.
	 */
	public class NetStreamDownloadableTrait extends DownloadableTrait
	{
		// Since NetStream does not dispatch ProgressEvent, NetStreamDownloadabletrait
		// will never be notified of the value change of bytesTotal. Therefore, 
		// this class actually does not dispatch BytesTotalChangeEvent.
		//
		public function NetStreamDownloadableTrait(netStream:NetStream)
		{
			super(NaN, NaN);
			
			_netStream = netStream;
		}
		
		/**
		 * @inheritDoc
		 */
		override public function get bytesDownloaded():Number
		{
			return _netStream.bytesLoaded;
		}
		
		/**
		 * @inheritDoc
		 */
		override public function get bytesTotal():Number
		{
			return _netStream.bytesTotal;
		}	
		
		//
		// Internals
		//
		
		private var _netStream:NetStream;	
	}
}