import matterStoreTest from './MatterStore.test';

// 保留原测试套件；DevEco 的测试运行配置调用此聚合入口。
export default function testsuite() {
  matterStoreTest();
}
