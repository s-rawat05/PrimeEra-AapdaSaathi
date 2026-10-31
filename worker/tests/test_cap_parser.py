"""CAP 1.2 parsing: real SACHET messages, demo fixtures, invalid and hostile XML."""

import pytest

from app.integrations.cap_parser import (
    CapParseError,
    area_polygons,
    lgd_district_codes,
    parse_cap,
    parse_polygon,
)


def test_real_sachet_update_message(cap_xml):
    a = parse_cap(cap_xml("sachet_uttarakhand_real_1793430002314009"))
    assert a.identifier == "IN-1793430002314009_9"
    assert a.sender == "Uttarakhand-SDMA" and a.status == "Actual" and a.msg_type == "Update"
    assert a.references[0].identifier == "IN-1793430002314009_65"
    assert a.is_valid, a.validation_errors
    info = a.primary_info("en")
    assert info.event == "Thunderstorm with Lightning" and info.severity == "Moderate"
    assert info.onset.utcoffset().total_seconds() == 5.5 * 3600
    assert info.instruction == "Please follow SDMA guidelines."
    assert "Polygon URL" in info.parameters
    codes = lgd_district_codes(a)
    assert "49" in codes and len(codes) >= 5
    assert area_polygons(a) == []  # SACHET publishes geometry separately; no inline polygon


def test_demo_fixture_multilingual_with_polygon(cap_xml):
    a = parse_cap(cap_xml("demo_flash_flood_alert"))
    assert a.status == "Exercise" and a.is_valid
    assert {i.language for i in a.infos} == {"en-IN", "hi-IN"}
    assert a.info_in("hi").headline.startswith("डेमो")
    rings = area_polygons(a)
    assert len(rings) == 1  # identical polygons in both languages are de-duplicated
    lon, lat = rings[0][0]
    assert (lat, lon) == (29.345, 79.551)  # CAP "lat,lon" converted to GeoJSON [lon, lat]


def test_update_and_cancel_references(cap_xml):
    up = parse_cap(cap_xml("demo_flash_flood_update"))
    cancel = parse_cap(cap_xml("demo_flash_flood_cancel"))
    assert up.msg_type == "Update" and up.references[0].identifier == "AAPDASAATHI-DEMO-FLOOD-0001"
    assert cancel.msg_type == "Cancel" and cancel.references[0].identifier == "AAPDASAATHI-DEMO-FLOOD-0002"


def test_malformed_xml_rejected():
    with pytest.raises(CapParseError, match="malformed"):
        parse_cap("<alert><identifier>x</alert>")


def test_not_cap_rejected():
    with pytest.raises(CapParseError, match="not a CAP"):
        parse_cap("<rss version='2.0'></rss>")


def test_entity_expansion_attack_rejected():
    bomb = """<?xml version="1.0"?>
<!DOCTYPE lolz [<!ENTITY lol "lol"><!ENTITY lol2 "&lol;&lol;&lol;&lol;">]>
<alert xmlns="urn:oasis:names:tc:emergency:cap:1.2"><identifier>&lol2;</identifier></alert>"""
    with pytest.raises(CapParseError, match="unsafe"):
        parse_cap(bomb)


def test_external_entity_rejected():
    xxe = """<?xml version="1.0"?>
<!DOCTYPE a [<!ENTITY x SYSTEM "file:///etc/passwd">]>
<alert xmlns="urn:oasis:names:tc:emergency:cap:1.2"><identifier>&x;</identifier></alert>"""
    with pytest.raises(CapParseError, match="unsafe"):
        parse_cap(xxe)


def test_validation_errors_collected_not_raised():
    xml = """<alert xmlns="urn:oasis:names:tc:emergency:cap:1.2">
<identifier>T-1</identifier><sender>s</sender><sent>2026-07-14T10:00:00</sent>
<status>Actual</status><msgType>Update</msgType><scope>Public</scope>
<info><category>Met</category><event>Rain</event><urgency>Soon</urgency><severity>Severe</severity>
<certainty>Likely</certainty></info></alert>"""
    a = parse_cap(xml)
    assert not a.is_valid
    joined = " ".join(a.validation_errors)
    assert "sent" in joined and "references" in joined and "urgency" in joined


@pytest.mark.parametrize(
    "bad", ["29.3,79.5 29.4,79.6 29.3,79.5", "29.3,79.5 29.4,79.6 29.5,79.7 29.6,79.8", "95,79 29,79 29,80 95,79"]
)
def test_invalid_polygons(bad):
    with pytest.raises(ValueError):
        parse_polygon(bad)
