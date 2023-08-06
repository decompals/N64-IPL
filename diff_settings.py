def apply(config, args):
    config['myimg'] = 'build/ipl3.HW1.bin'
    config['baseimg'] = 'ipl3.HW1.bin'
    config['makeflags'] = ['COMPARE=0']
    config['source_directories'] = ['src', 'include']
