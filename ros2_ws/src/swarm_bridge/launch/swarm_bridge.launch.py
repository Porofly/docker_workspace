import os
from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    drone_id = int(os.environ.get('DRONE_ID', '1'))

    return LaunchDescription([
        Node(
            package='swarm_bridge',
            executable='bridge_node',
            name='swarm_bridge',
            parameters=[{'drone_id': drone_id}],
            output='screen',
        ),
    ])
