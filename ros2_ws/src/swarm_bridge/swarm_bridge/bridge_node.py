import json
import os
import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, HistoryPolicy

from geometry_msgs.msg import PoseStamped
from std_msgs.msg import String
from px4_msgs.msg import VehicleLocalPosition, VehicleStatus


class SwarmBridge(Node):
    """PX4 내부 토픽을 swarm 공유 토픽으로 브릿지하는 노드.

    구독 (내부):
        /px4_{id}/fmu/out/vehicle_local_position_v1 -> /swarm/drone_{id}/pose (10Hz)
        /px4_{id}/fmu/out/vehicle_status_v1         -> /swarm/drone_{id}/status (1Hz)
    """

    def __init__(self):
        # DRONE_ID를 환경변수에서 읽어 노드 이름에 포함
        drone_id = int(os.environ.get('DRONE_ID', '1'))
        super().__init__(f'swarm_bridge_drone_{drone_id}')

        self.drone_id = drone_id
        self.get_logger().info(f'Swarm Bridge started for drone_{self.drone_id}')

        # QoS: BEST_EFFORT
        BEST_EFFORT = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
        )

        px4_ns = f'/px4_{drone_id}'

        # --- Pose Bridge ---
        # 구독: PX4 로컬 위치 (/px4_{N}/fmu/out/vehicle_local_position_v1)
        self.sub_local_pos = self.create_subscription(
            VehicleLocalPosition,
            f'{px4_ns}/fmu/out/vehicle_local_position_v1',
            self.local_position_callback,
            BEST_EFFORT,
        )

        # 발행: swarm pose (10Hz throttle)
        self.pub_pose = self.create_publisher(
            PoseStamped,
            f'/swarm/drone_{self.drone_id}/pose',
            BEST_EFFORT,
        )

        # Pose throttle: 10Hz (PX4는 ~50Hz로 발행하므로 다운샘플링)
        self.pose_timer = self.create_timer(0.1, self.publish_pose)
        self.latest_local_pos = None

        # --- Status Bridge ---
        # 구독: PX4 기체 상태 (/px4_{N}/fmu/out/vehicle_status_v1)
        self.sub_vehicle_status = self.create_subscription(
            VehicleStatus,
            f'{px4_ns}/fmu/out/vehicle_status_v1',
            self.vehicle_status_callback,
            BEST_EFFORT,
        )

        # 발행: swarm status (1Hz)
        self.pub_status = self.create_publisher(
            String,
            f'/swarm/drone_{self.drone_id}/status',
            BEST_EFFORT,
        )

        self.status_timer = self.create_timer(1.0, self.publish_status)
        self.latest_vehicle_status = None

    def local_position_callback(self, msg: VehicleLocalPosition):
        self.latest_local_pos = msg

    def publish_pose(self):
        if self.latest_local_pos is None:
            return

        msg = self.latest_local_pos
        pose = PoseStamped()
        pose.header.stamp = self.get_clock().now().to_msg()
        pose.header.frame_id = f'drone_{self.drone_id}/local'

        # PX4 NED -> ROS2 ENU 변환
        pose.pose.position.x = msg.y     # NED.E -> ENU.X
        pose.pose.position.y = msg.x     # NED.N -> ENU.Y
        pose.pose.position.z = -msg.z    # NED.D -> ENU.Z (부호 반전)

        self.pub_pose.publish(pose)

    def vehicle_status_callback(self, msg: VehicleStatus):
        self.latest_vehicle_status = msg

    def publish_status(self):
        if self.latest_vehicle_status is None:
            return

        msg = self.latest_vehicle_status
        status = String()
        status.data = json.dumps({
            'drone_id': self.drone_id,
            'timestamp': self.get_clock().now().nanoseconds,
            'arming_state': int(msg.arming_state),
            'nav_state': int(msg.nav_state),
            'failsafe': bool(msg.failsafe),
        })

        self.pub_status.publish(status)


def main(args=None):
    rclpy.init(args=args)
    node = SwarmBridge()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
