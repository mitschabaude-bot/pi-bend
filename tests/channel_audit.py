"""Test-only channel ownership instrumentation for generated Bend JavaScript."""
def instrument(source):
    opened='function chan_new(room) {\n'
    closed='if (!row.shut) {\n    chan_shut(row);'
    assert source.count(opened)==1 and source.count(closed)==1
    source=source.replace(opened,opened+'  globalThis.PAIR_CHANNELS++;\n',1)
    source=source.replace(closed,'if (!row.shut) {\n    globalThis.PAIR_CHANNELS--;\n    chan_shut(row);',1)
    return 'globalThis.PAIR_CHANNELS=0;\nprocess.on("exit",()=>console.error(`AUDIT ${globalThis.PAIR_CHANNELS} ${globalThis.BEND_IO.live} ${globalThis.BEND_IO.waits.length}`));\n'+source
