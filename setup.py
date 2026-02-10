from setuptools import setup

APP = ["textfix_app.py"]
OPTIONS = {
    "argv_emulation": False,
    "plist": {
        "CFBundleName": "TextFix",
        "CFBundleDisplayName": "TextFix",
        "CFBundleIdentifier": "com.textfix.app",
        "CFBundleShortVersionString": "0.1.0",
        "LSUIElement": True,
    },
}

setup(
    app=APP,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
