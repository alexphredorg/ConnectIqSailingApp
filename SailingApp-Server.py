#!/usr/bin/env python
import logging
import os
import sys
import socket
import struct
from urlparse import urlparse

import tornado.httpserver
import tornado.ioloop
import tornado.iostream
import tornado.web
import tornado.httpclient
import tornado.httputil

from libtcd.api import Tcd
from libtcd.api import NodeFactor, NodeFactors
from libtcd.api import ReferenceStation

from math import radians, cos, sin, asin, sqrt, log10, floor

TCD_FILENAME='/usr/share/xtide/harmonics-dwf-20100529-free.tcd'


__all__ = ['MainHandler', 'run_server']
__tcd__ = Tcd.open(TCD_FILENAME)
# dict of stations, key is station id
__tcd_stations__ = {}

def roundsig(x, n=8):
    if not x: return 0
    power = -int(floor(log10(abs(x)))) + (n - 1)
    factor = (10 ** power)
    return round(x * factor) / factor

#
# CalTopoHandler fetches a custom map from CalTopo and pulls the 
# markers and folders out and structures them into the format that
# the SailingApp on the watch wants.  
#
# URL format: /CalTopo/{calTopoMapId}
#
# output JSON:
# { groups: [ { folderName: name, marks: [ { name:name, y:lat, x:lon } ] } ] }
# or on error:
# { error: errorText }
#
class CalTopoHandler(tornado.web.RequestHandler):
    @tornado.web.asynchronous
    def get(self, caltopoId=None):
        if caltopoId == None:
            raise tornado.web.HTTPError(500) 
        http = tornado.httpclient.AsyncHTTPClient()
        print("Called by http://:18266/CalTopo/" + caltopoId)
        caltopoUrl = "https://caltopo.com/m/" + caltopoId + "?format=json"
        print("fetching: " + caltopoUrl)
        http.fetch(caltopoUrl, callback=self.on_response)
    
    def on_response(self, response):
        if response.error: raise tornado.web.HTTPError(500)
        mapData = tornado.escape.json_decode(response.body)
        mapDataFeatures = mapData["features"]

        folders = {}
        # find all folders first
        for feature in mapDataFeatures:
            properties = feature['properties']
            classType = properties['class']
            featureId = feature['id']
            if classType == 'Folder':
                name = properties['title']
                folders[featureId] = { 'name':name, 'marks': [] }

        # find all marks second
        for feature in mapDataFeatures:
            properties = feature['properties']
            classType = properties['class']
            if classType == 'Marker':
                name = properties['title']
                if 'description' in properties:
                    name = name + ':' + properties['description']

                # create a folder if one doesn't exist
                if 'folderId' not in properties: 
                    properties['folderId'] = -1
                    if -1 not in folders:
                        folders[-1] = { "name":"marks", "marks": [] }

                # load rest of features
                geometry = feature['geometry']
                lat = geometry['coordinates'][1]
                lon = geometry['coordinates'][0]

                # create mark
                m = {'n':name, 'lat':roundsig(lat), 'lon':roundsig(lon)}

                # update folder
                folderId = properties['folderId']
                folders[folderId]["marks"].append(m)

        folderList = []
        for folderId in folders:
            folders[folderId]["marks"] = sorted(folders[folderId]["marks"], key=lambda m: m["n"])
            folderList.append(folders[folderId])

        returnData = {"groups":folderList }
        json = tornado.escape.json_encode(returnData)
        self.write(json)
        self.finish()


    def on_response_old_format(self, response):
        if response.error: raise tornado.web.HTTPError(500)
        mapData = tornado.escape.json_decode(response.body)
        mapDataFolder = mapData["Folder"]
        mapDataMarker = mapData["Marker"]

        folders = {}
        for folder in mapDataFolder:
            folders[folder["id"]] = { "name":folder["label"], "marks": [] }

        for mark in mapDataMarker:
            name = mark["label"]

            # incorporate the comment into the name if it was specified
            if "comments" in mark:
                name = mark["label"] + ":" + mark["comments"]

            # make a default folder if one wasn't specified
            if "folderId" not in mark:
                mark["folderId"] = -1
                if -1 not in folders:
                    folders[-1] = { "name":"marks", "marks": [] }
            m = { 
                "n":name,
                "lat":roundsig(mark["position"]["lat"]),
                "lon":roundsig(mark["position"]["lng"])
            }
            folderId = mark["folderId"]
            folders[folderId]["marks"].append(m)

        folderList = []
        for folderId in folders:
            folders[folderId]["marks"] = sorted(folders[folderId]["marks"], key=lambda m: m["n"])
            folderList.append(folders[folderId])

        returnData = {"groups":folderList }

        json = tornado.escape.json_encode(returnData)
            
        self.write(json)
        self.finish()

#
# Return all of the tide stations available near a point on the earth
# sorted by distance
#
# URL format: /TideStations/{lat},{lon}
#
# output JSON:
# { stations: [ { id: id, name:name, distance:distanceInKm } ] }
# or on error:
# { error: errorText }
#
class TideStationsHandler(tornado.web.RequestHandler):
    def get(self, latlon=None):
        if latlon == None:
            raise tornado.web.HTTPError(500) 
        latlon = latlon.split(',')
        lat = float(latlon[0])
        lon = float(latlon[1])
        stations = [];
        print("tide station search near: %f,%f" % (lat,lon))
        for id,t in __tcd_stations__.items():
            km = self.measureDistance(lat, lon, t.latitude, t.longitude)
            if km < 2000:
                station = { "id":t.record_number, "name":t.name, "distance":km }
                stations.append(station)

        stations = sorted(stations, key=lambda station: station["distance"])
        if len(stations) > 10: stations = stations[0:9]
        returnData = {"stations":stations}
        json = tornado.escape.json_encode(returnData)

        self.write(json)
        self.finish()

    def measureDistance(self, lat1, lon1, lat2, lon2):
        """
        Calculate the great circle distance between two points 
        on the earth (specified in decimal degrees)
        """
        # convert decimal degrees to radians 
        lon1, lat1, lon2, lat2 = map(radians, [lon1, lat1, lon2, lat2])
        # haversine formula 
        dlon = lon2 - lon1 
        dlat = lat2 - lat1 
        a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
        c = 2 * asin(sqrt(a)) 
        km = 6367 * c
        return km

#
# Return all of the data necessary to compute tides for a tide station
#
# URL format: /TideStation/{id}
# id is a station ID from /TideStations/{lat},{lon}
#
# output JSON:
# { station:{ id:, name:, zone_offset:, datum:[], 
#    amp:[], epoch:[], speed:[], years:[], 
#    equilibrium:{ []..[] }, node_factor:{ []..[] }
# dict index into equilibrium and node_factor is the year for those 
# parameters
# or on error:
# { error: errorText }
#
class TideStationHandler(tornado.web.RequestHandler):
    def get(self, id):
        if id == None:
            returnData = {"error":"no station id specified"}
            self.write(tornado.escape.json_encode(returnData))
            self.finish()
            return

        id = int(id)
        if id not in __tcd_stations__:
            returnData = {"error":"invalid station id"}
            self.write(tornado.escape.json_encode(returnData))
            self.finish()
            return

        station = __tcd_stations__[id]

        amp = []
        epoch = []
        speed = []
        e = {}
        n = {}
        years=range(2017, 2020)

        for co in station.coefficients:
            amp.append(roundsig(co.amplitude, 6))
            epoch.append(roundsig(co.epoch, 6))
            speed.append(roundsig(co.constituent.speed, 6))

        for y in years:
            e[y] = []
            n[y] = []
            for co in station.coefficients:
                e[y].append(roundsig(co.constituent.node_factors[y].equilibrium, 6))
                n[y].append(roundsig(co.constituent.node_factors[y].node_factor, 5))

        zone_offset = station.zone_offset.total_seconds() / 60

        d = {
            "id":id,
            "name":station.name,
            "zone_offset":zone_offset,
            "datum":roundsig(station.datum_offset, 5),
            "amp":amp,
            "epoch":epoch,
            "speed":speed,
            "years":years,
            "equilibrium":e,
            "node_factor":n
        }

        returnData = {"station":d}
        json = tornado.escape.json_encode(returnData)
                
        self.write(json)
        self.finish()

    # round a floating point number down to 4 trailing digits.  This 
    # is to reduce the size of the return structure.
    def round(self, f):
        return float("%.4f" % f)

# start the web server
def run_server(port, start_ioloop=True):
    app = tornado.web.Application([
        (r'/CalTopo/([\d\w]{1,8})$', CalTopoHandler),
        (r'/TideStations/([-\d\.]+\,[-\d\.]+)$', TideStationsHandler),
        (r'/TideStation/(\d+)$', TideStationHandler),
    ])
    app.listen(port)
    ioloop = tornado.ioloop.IOLoop.instance()
    if start_ioloop:
        ioloop.start()

if __name__ == '__main__':
    # cache the stations that we can actually work with into an in-memory dict
    for t in __tcd__:
        if type(t) is ReferenceStation and 'Current' not in t.name:
            __tcd_stations__[t.record_number] = t
    print("There are %i reference tide stations" % len(__tcd_stations__))

    # parse cmdline parameters
    port = 18266
    if len(sys.argv) > 1:
        port = int(sys.argv[1])

    # start the web server
    print("Starting SailingApp on port %d" % port)
    run_server(port)
