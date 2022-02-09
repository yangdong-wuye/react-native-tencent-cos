export class Token {
  pause: boolean;

  constructor() {
    this.pause = false;
  }

  onPause() {
    this.pause = true;
  }

  onResume() {
    this.pause = false;
  }
}
