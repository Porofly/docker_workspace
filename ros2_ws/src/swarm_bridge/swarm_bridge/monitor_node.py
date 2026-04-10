import json
import os
import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy

from geometry_msgs.msg import PoseStamped
from std_msgs.msg import String


NUM_DRONES = 5


class SwarmMonitor(Node):
    """다른 드론들의 pose/status를 구독하여 로그에 출력하는 노드."""

    def __init__(self):
        drone_id = int(os.environ.get('DRONE_ID', '1'))
        super().__init__(f'swarm_monitor_drone_{drone_id}')

        self.drone_id = drone_id
        self.get_logger().info(f'Swarm Monitor started for drone_{self.drone_id}')

        qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
        )

        # 자신을 제외한 모든 드론의 토픽 구독
        self.pose_subs = {}
        self.status_subs = {}

        for other_id in range(1, NUM_DRONES + 1):
            if other_id == self.drone_id:
                continue

            pose_topic = f'/swarm/drone_{other_id}/pose'
            status_topic = f'/swarm/drone_{other_id}/status'

            self.pose_subs[other_id] = self.create_subscription(
                PoseStamped,
                pose_topic,
                lambda msg, did=other_id: self.pose_callback(did, msg),
                qos,
            )

            self.status_subs[other_id] = self.create_subscription(
                String,
                status_topic,
                lambda msg, did=other_id: self.status_callback(did, msg),
                qos,
            )

            self.get_logger().info(f'Subscribed to drone_{other_id} (pose, status)')

    def pose_callback(self, other_id: int, msg: PoseStamped):
        p = msg.pose.position
        self.get_logger().info(
            f'[drone_{other_id}] pose: x={p.x:.2f}, y={p.y:.2f}, z={p.z:.2f}'
        )

    def status_callback(self, other_id: int, msg: String):
        try:
            data = json.loads(msg.data)
            self.get_logger().info(
                f'[drone_{other_id}] status: arming={data.get("arming_state")}, '
                f'nav={data.get("nav_state")}, failsafe={data.get("failsafe")}'
            )
        except json.JSONDecodeError:
            self.get_logger().warn(f'[drone_{other_id}] invalid status JSON')


def main(args=None):
    rclpy.init(args=args)
    node = SwarmMonitor()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
