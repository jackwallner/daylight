#!/usr/bin/env python3
"""Configure the nonlocalized Daylight Left App Store listing fields."""
from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib as A  # noqa: E402


BUNDLE_ID = "com.jackwallner.daylight"
APP_NAME = "Daylight Left"
# Age-rating answers are copied from a live health app and then overridden
# below. This pointed at the retired Protein Tracker record, so the copy
# would start failing the moment that record went away.
AGE_TEMPLATE_BUNDLE_ID = os.environ.get(
    "ASC_AGE_TEMPLATE_BUNDLE_ID", "com.jackwallner.vitals"
)
REVIEW_NOTES = """Daylight reads HealthKit's Time in Daylight, sleep analysis, steps, Apple exercise time, active energy, resting heart rate, heart-rate variability, and respiratory rate. It never writes to Apple Health or uploads Health data.

TO TEST WITHOUT HEALTH DATA: complete onboarding and open Today. The screen works with no Apple Health samples at all. It shows how much daylight is left before sunset, today's sunrise and sunset, the day length, and the latest time you could head out to reach your daily target. Only the "minutes spent in daylight" figure needs Health data.

TIME IN DAYLIGHT is recorded by Apple Watch using its ambient light sensor. A reviewer testing on iPhone alone will see zero minutes spent, and the app says so explicitly rather than implying the user stayed indoors.

PERMISSIONS: onboarding asks for read-only HealthKit access and, separately, one approximate location fix. Both are skippable. Time in Daylight powers the free daily total. The other Health types power the Daylight+ Personal Daylight Model. Location is used only to compute sunrise and sunset on device. No location or Health data leaves the device, and there is no background location tracking.

NO ACCOUNT IS REQUIRED. There is no login, ad network, or server storing anything.

TODAY'S NUMBERS ARE FREE. Daylight remaining, the sunrise and sunset times, the daily target, the head-out-by time, source controls, widgets, complications, and seven days of history all work with no purchase.

DAYLIGHT+ is an optional monthly or yearly subscription, each with a 7-day free trial for eligible customers, or a one-time lifetime purchase. It adds the on-device Personal Daylight Model, history past seven days, the month-over-month daylight comparison, and a reminder before the daily deadline.

The Personal Daylight Model compares the user's recorded signals, leaves missing data out, applies a conservative uncertainty check across all eight signals, and may report no clear relationship. Its results are observational and do not prove that daylight caused a change.

Sunrise and sunset are astronomical calculations. Minutes in daylight are reported from Apple Health. The app does not diagnose, treat, cure, or prevent anything, and makes no claim that daylight improves mood, sleep, vitamin D, or eyesight."""


def review_phone() -> str:
    """The App Review contact number, which never belongs in a public repo.

    Sourced from ASC_REVIEW_PHONE, or from the shell-sourced
    ``~/.daylight_credentials`` that the other scripts here already read.
    """
    value = os.environ.get("ASC_REVIEW_PHONE")
    if value:
        return value.strip()
    path = Path.home() / ".daylight_credentials"
    if path.exists():
        for line in path.read_text().splitlines():
            key, _, raw = line.partition("=")
            key = key.strip().removeprefix("export ").strip()
            if key == "ASC_REVIEW_PHONE":
                return raw.strip().strip('"').strip("'")
    raise SystemExit(
        "error: set ASC_REVIEW_PHONE, or add it to ~/.daylight_credentials.\n"
        "The App Review contact number is deliberately not stored in this repo."
    )


def main() -> None:
    client = A.ASCClient.from_credentials()
    app = A.find_app(client, BUNDLE_ID)
    info = A.find_editable_app_info(client, app["id"])
    version = A.find_editable_version(client, app["id"])
    if not info or not version:
        raise SystemExit("error: Daylight Left needs an editable app info and version")

    client.patch(
        f"/apps/{app['id']}",
        {
            "data": {
                "type": "apps",
                "id": app["id"],
                "attributes": {
                    "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT",
                },
            }
        },
    )
    client.patch(
        f"/appStoreVersions/{version['id']}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": version["id"],
                "attributes": {
                    "copyright": "2026 Jack Wallner",
                    "releaseType": "MANUAL",
                },
            }
        },
    )
    age = client.get(f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    template_app = A.find_app(client, AGE_TEMPLATE_BUNDLE_ID)
    template_info = A.find_editable_app_info(client, template_app["id"])
    template_age = client.get(
        f"/appInfos/{template_info['id']}/ageRatingDeclaration"
    )["data"]["attributes"]
    attrs = {key: value for key, value in template_age.items() if value is not None}
    attrs.pop("ageRatingOverride", None)
    attrs.update(
        {
            "healthOrWellnessTopics": True,
            "medicalOrTreatmentInformation": "NONE",
            "alcoholTobaccoOrDrugUseOrReferences": "NONE",
        }
    )
    client.patch(
        f"/ageRatingDeclarations/{age['id']}",
        {
            "data": {
                "type": "ageRatingDeclarations",
                "id": age["id"],
                "attributes": attrs,
            }
        },
    )

    review = client.get(f"/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    attributes = {
        "contactFirstName": "Jack",
        "contactLastName": "Wallner",
        "contactPhone": review_phone(),
        "contactEmail": "jackwallner@gmail.com",
        "demoAccountRequired": False,
        "notes": REVIEW_NOTES,
    }
    if review:
        client.patch(
            f"/appStoreReviewDetails/{review['id']}",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "id": review["id"],
                    "attributes": attributes,
                }
            },
        )
    else:
        client.post(
            "/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": attributes,
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version["id"]}
                        }
                    },
                }
            },
        )
    print(f"configured {APP_NAME} ({app['id']})")


if __name__ == "__main__":
    main()
