from setuptools import find_packages, setup
import os
from glob import glob

package_name = 'swarm_bridge'

setup(
    name=package_name,
    version='0.1.0',
    packages=find_packages(),
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        (os.path.join('share', package_name, 'launch'), glob('launch/*.py')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='kyg',
    maintainer_email='kyg@todo.todo',
    description='Bridge between PX4 internal topics and swarm shared topics',
    license='MIT',
    entry_points={
        'console_scripts': [
            'bridge_node = swarm_bridge.bridge_node:main',
        ],
    },
)
