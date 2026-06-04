# syntax=docker/dockerfile:1
# =============================================================================
# LabVIEW CI Linux image for challenge-of-champions
# =============================================================================
# Extends the official NI LabVIEW Linux container with:
#   - VI Analyzer support package (ni-vialin-labview-support) via nipkg
#
# Build args:
#   NIPM_FEED_URL        – nipkg feed for the installed LabVIEW version
#   VIA_SUPPORT_PACKAGE  – nipkg package name for VI Analyzer support
# =============================================================================

ARG NIPM_FEED_URL=https://download.ni.com/support/nipkg/products/ni-l/ni-labview-2026/26.1/released
ARG VIA_SUPPORT_PACKAGE=ni-vialin-labview-support

FROM nationalinstruments/labview:latest-linux

ARG NIPM_FEED_URL
ARG VIA_SUPPORT_PACKAGE

# ---------------------------------------------------------------------------- #
# Install VI Analyzer support via nipkg
# ---------------------------------------------------------------------------- #
RUN set -ex \
 && echo "Adding nipkg feed: ${NIPM_FEED_URL}" \
 && nipkg feed-add --name=ni-labview-via "${NIPM_FEED_URL}" \
 && echo "Updating package lists..." \
 && nipkg update \
 && echo "Installing ${VIA_SUPPORT_PACKAGE} ..." \
 && nipkg install --accept-eulas --no-progress "${VIA_SUPPORT_PACKAGE}" \
 && echo "VI Analyzer support installed: ${VIA_SUPPORT_PACKAGE}"
