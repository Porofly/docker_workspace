from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        Node(
            package='swarm_bridge',
            executable='bridge_node',
            output='screen',
        ),
    ])
