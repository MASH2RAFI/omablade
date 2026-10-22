.pragma library

var manifest = {
  "schemaVersion": 1,
  "id": "example.sample-images",
  "name": "Sample Images",
  "version": "0.1.0",
  "author": "MASH2RAFI",
  "license": "MIT",
  "description": "A sample illustration library in an Omablade blade: synced from Google Drive, searchable, browsable by month",
  "kinds": [
    "service",
    "bar-widget"
  ],
  "entryPoints": {
    "service": "Service.qml",
    "barWidget": "SampleBarWidget.qml"
  },
  "extensions": {
    "mash2rafi.omablade/helper": [
      {
        "id": "catalog",
        "entry": "bin/sample-imagesctl",
        "read": [
          "list",
          "status"
        ],
        "timeoutMs": 20000
      }
    ],
    "mash2rafi.omablade/blade": [
      {
        "id": "sample-images",
        "name": "Samples",
        "glyph": "\udb80\udee9",
        "icon": "assets/sample.svg",
        "description": "Sample illustrations from the local library, synced from Google Drive",
        "entry": "blades/Module.qml",
        "provider": "Provider.qml",
        "singleton": true,
        "minHeight": 200,
        "hostContract": 2,
        "settings": {
          "defaults": {
            "library": "~/.claude/skills/sample-images",
            "stackLayers": true
          },
          "schema": [
            {
              "key": "library",
              "type": "path",
              "label": "Library",
              "description": "Folder holding index.json and the images; the sample-images skill library by default",
              "maxLength": 1024,
              "placeholder": "~/.claude/skills/sample-images"
            },
            {
              "key": "stackLayers",
              "type": "boolean",
              "label": "Stack layers and copies",
              "description": "Show one image per drawing: the composed scene instead of its layers, the full-size file instead of its copies"
            }
          ]
        }
      }
    ]
  },
  "barWidget": {
    "displayName": "Samples",
    "description": "The sample library as a dropdown under a bar icon, hosted by Omablade",
    "category": "Plugin",
    "allowMultiple": false,
    "defaults": {
      "showNavbarIcon": false,
      "module": "example.sample-images/sample-images",
      "glyph": "",
      "width": 460,
      "height": 600
    },
    "schema": [
      {
        "key": "showNavbarIcon",
        "type": "boolean",
        "label": "Show navbar icon",
        "description": "Show the optional Samples dropdown in this bar. The Omablade extension remains available when hidden."
      },
      {
        "key": "module",
        "type": "string",
        "label": "Module",
        "description": "Omablade module id to pop out; any module works here",
        "maxLength": 128
      },
      {
        "key": "glyph",
        "type": "string",
        "label": "Glyph",
        "description": "Bar glyph override; empty draws the sample icon",
        "maxLength": 16
      },
      {
        "key": "width",
        "type": "integer",
        "label": "Width",
        "min": 240,
        "max": 1600,
        "step": 20
      },
      {
        "key": "height",
        "type": "integer",
        "label": "Height",
        "min": 160,
        "max": 1600,
        "step": 20
      }
    ]
  }
}
