Installer installUrl: 'http://source.squeak.org/trunk/Nebraska-ul.35.mcz'.

HDTestReport runPackage: 'Nebraska-Network-ObjectSocket'.

"Throw away the dirty image."
WorldState addDeferredUIMessage: [ SmalltalkImage current snapshot: false andQuit: true ].