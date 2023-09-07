def apply(config, args):
    config['myimg'] = 'build/ipl3.GCC.bin'
    config['baseimg'] = 'ipl3.GCC.bin'
    config['makeflags'] = ['COMPARE=0']
    config['source_directories'] = ['src', 'include']
