//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <cstring>
#include <satcat5/coap_reader.h>
#include <satcat5/coap_resource.h>
#include <satcat5/coap_writer.h>
#include <satcat5/log.h>

using satcat5::coap::Resource;
using satcat5::coap::ResourceEcho;
using satcat5::coap::ResourceLog;
using satcat5::coap::ResourceServer;
namespace log = satcat5::log;

bool Resource::operator==(const Resource& other) const {
    // Uri-Path must match, be null-terminated, and less than max length
    // Some of this validation should happen when Uri-Path is first provided,
    // set m_uri_path during the add_resource() call in the Server? Would also
    // allow to drop leading '/', which is a common convention
    return strncmp(m_uri_path, other.m_uri_path,
        SATCAT5_COAP_MAX_URI_PATH_LEN) == 0 &&
        memchr(m_uri_path, '\0', SATCAT5_COAP_MAX_URI_PATH_LEN + 1) &&
        memchr(other.m_uri_path, '\0', SATCAT5_COAP_MAX_URI_PATH_LEN + 1);
}

bool ResourceEcho::request_get(Connection* obj, Reader& msg) {
    // Return 2.05 Content with the payload copied
    Writer reply(obj->open_response());
    if (!reply.ready()) { return false; }
    u8 type = msg.type() == TYPE_CON ? TYPE_ACK : TYPE_NON;
    bool ok = reply.write_header(type, CODE_CONTENT, msg);
    if (ok) { ok = reply.write_option(OPTION_FORMAT, FORMAT_BYTES); }
    satcat5::io::Readable* src = msg.read_data();
    satcat5::io::Writeable* dst = reply.write_data();
    if (!ok || !src || !dst) { return false; }
    return src->copy_to(dst) && reply.write_finalize();
}

bool ResourceLog::request_post(Connection* obj, Reader& msg) {
    // Validate Content-Format
    if (msg.format() && msg.format().value() != FORMAT_TEXT) {
        return obj->error_response(CODE_BAD_FORMAT, msg);
    }

    // Write a log entry with a useful prefix, source IP would be better?
    satcat5::io::ArrayWriteStatic<SATCAT5_COAP_BUFFSIZE> log_str;
    satcat5::io::Readable* src = nullptr;
    if (!(src = msg.read_data()) || !src->get_read_ready()) {
        return obj->error_response(CODE_BAD_REQUEST, msg, "No message given");
    }
    src->copy_to(&log_str);
    log_str.write_u8(0); // Ensure null termination
    log::Log(m_priority, m_uri_path).write(": ")
        .write((const char*) log_str.buffer());

    // Return 2.01 Created
    Writer reply(obj->open_response());
    if (!reply.ready()) { return false; }
    u8 type = msg.type() == TYPE_CON ? TYPE_ACK : TYPE_NON;
    bool ok = reply.write_header(type, CODE_CREATED, msg);
    return ok && reply.write_finalize();
}

void ResourceServer::coap_request(Connection* obj, Reader& msg) {

    // Look up the parsed Uri-Path against the server's registered resources
    Resource target_resource(msg.uri_path().value_or("")); // Empty is valid
    Resource* matched_resource = nullptr;
    Resource* resource = m_resources.head();
    while (resource) {
        if (*resource == target_resource) {
            matched_resource = resource; break;
        }
        resource = m_resources.next(resource);
    }

    // Return an error if no resources matched
    if (!matched_resource) {
        obj->error_response(CODE_NOT_FOUND, msg, "Unrecognized Uri-Path");
        return;
    }

    // The found resource may generate a response, sent as a piggybacked reply
    bool ok;
    if (msg.code() == CODE_GET) {
        ok = matched_resource->request_get(obj, msg);
    } else if (msg.code() == CODE_PUT) {
        ok = matched_resource->request_put(obj, msg);
    } else if (msg.code() == CODE_POST) {
        ok = matched_resource->request_post(obj, msg);
    } else if (msg.code() == CODE_DELETE) {
        ok = matched_resource->request_delete(obj, msg);
    } else { // Reject per Section 5.8
        ok = obj->error_response(CODE_BAD_METHOD, msg);
    }

    // Send 5.00 SERVER_ERROR if the Resource failed to generate a response
    if (!ok) {
        obj->error_response(CODE_SERVER_ERROR, msg); // GCOVR_EXCL_LINE
    }
}
