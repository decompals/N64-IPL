def apply(config, args):
    config['myimg'] = 'build/pifrom.NTSC.bin'
    config['baseimg'] = 'pifrom.NTSC.bin'
    config['makeflags'] = ['COMPARE=0']
    config['source_directories'] = ['src', 'include']
