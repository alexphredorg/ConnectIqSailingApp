#!/usr/bin/python
from libtcd.api import Tcd
from libtcd.api import NodeFactor, NodeFactors
from pprint import pprint
import struct

TCD_FILENAME='/usr/share/xtide/harmonics-dwf-20100529-free.tcd'

years=range(2016, 2025)

stations = [
	{
		'longname': 'Port Townsend (Point Hudson), Admiralty Inlet, Washington',
		'shortname': 'Port Townsend (Pt Hudson)',
		'classname': 'PortTownsend'
	},
	{
		'longname': 'Tacoma, Commencement Bay, Sitcum Waterway, Puget Sound, Washington',
		'shortname': 'Tacoma (C''ment Bay)',
		'classname': 'Tacoma'
	},
	{
		'longname': 'Friday Harbor, San Juan Island, San Juan Channel, Washington',
		'shortname': 'Friday Harbor',
		'classname': 'FridayHarbor'
	},
	{
		'longname': 'Neah Bay, Strait Of Juan De Fuca, Washington',
		'shortname': 'Neah Bay',
		'classname': 'NeahBay'
	},
	{
		'longname': 'Port Angeles, Strait Of Juan De Fuca, Washington',
		'shortname': 'Port Angeles',
		'classname': 'PortAngeles'
	},
	{
		'longname': 'Seattle, Puget Sound, Washington',
		'shortname': 'Seattle',
		'classname': 'Seattle'
	}
    ];


for station in stations:
    longname = station['longname']
    shortname = station['shortname']
    classname = station['classname']

    tcd = Tcd.open(TCD_FILENAME)
    tideRecord = tcd.find(longname)
    amp = []
    epoch = []
    speed = []

    for co in tideRecord.coefficients:
        amp.append("%.4f" % co.amplitude)
        epoch.append("%.3f" % co.epoch)
        speed.append("%.4f" % co.constituent.speed)

    equil_code = ""
    node_factor_code = ""

    for y in years:
        sub_e = []
        sub_n = []
        for co in tideRecord.coefficients:
            e = struct.pack('f', co.constituent.node_factors[y].equilibrium)
            n = struct.pack('f', co.constituent.node_factors[y].node_factor)
            sub_e.append("%.4f" % struct.unpack('f', e)[0])
            sub_n.append("%.4f" % struct.unpack('f', n)[0])

        equil_code += "\t\tif (year == " + str(y) + ") {\n"
        equil_code += "\t\t\treturn" + str(sub_e) + ";\n"
        equil_code += "\t\t}\n"
        node_factor_code += "\t\tif (year == " + str(y) + ") {\n"
        node_factor_code += "\t\t\treturn" + str(sub_n) + ";\n"
        node_factor_code += "\t\t}\n"

    d = {}
    d['className'] = classname
    d['gmt_offset'] = 8
    d['station_id'] = tideRecord.station_id
    d['station_name'] = shortname
    d['tzfile'] = tideRecord.tzfile
    d['zone_offset'] = tideRecord.zone_offset
    d['datum'] = tideRecord.datum_offset
    d['amp'] = amp
    d['epoch'] = epoch
    d['speed'] = speed
    d['equil_code'] = equil_code
    d['node_factor_code'] = node_factor_code

    with open("template.mc", "r") as ftemp:
        template = ftemp.read()

    print template.format(**d)
