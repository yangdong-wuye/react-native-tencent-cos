import { NativeModules } from 'react-native';

type TencentCosType = {
  multiply(a: number, b: number): Promise<number>;
};

const { TencentCos } = NativeModules;

export default TencentCos as TencentCosType;
