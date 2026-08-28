declare global {
  interface PromiseConstructor {
    withResolvers?<T>(): {
      promise: Promise<T>;
      resolve: (value: T | PromiseLike<T>) => void;
      reject: (reason?: unknown) => void;
    };
  }

  interface Array<T> {
    at?(index: number): T | undefined;
  }

  interface ObjectConstructor {
    hasOwn?(object: object, property: PropertyKey): boolean;
  }

  interface String {
    replaceAll?(
      searchValue: string | RegExp,
      replaceValue: string | ((substring: string, ...args: unknown[]) => string),
    ): string;
  }
}

if (!Promise.withResolvers) {
  Promise.withResolvers = function withResolvers<T>() {
    let resolve!: (value: T | PromiseLike<T>) => void;
    let reject!: (reason?: unknown) => void;
    const promise = new Promise<T>((resolvePromise, rejectPromise) => {
      resolve = resolvePromise;
      reject = rejectPromise;
    });
    return { promise, resolve, reject };
  };
}

if (!Array.prototype.at) {
  Object.defineProperty(Array.prototype, "at", {
    configurable: true,
    writable: true,
    value<T>(this: T[], index: number): T | undefined {
      const normalized = Math.trunc(index) || 0;
      const position = normalized < 0 ? this.length + normalized : normalized;
      return position < 0 || position >= this.length ? undefined : this[position];
    },
  });
}

if (!Object.hasOwn) {
  Object.hasOwn = (object: object, property: PropertyKey) =>
    Object.prototype.hasOwnProperty.call(object, property);
}

if (!String.prototype.replaceAll) {
  Object.defineProperty(String.prototype, "replaceAll", {
    configurable: true,
    writable: true,
    value(
      this: string,
      searchValue: string | RegExp,
      replaceValue: string | ((substring: string, ...args: unknown[]) => string),
    ) {
      if (searchValue instanceof RegExp) {
        if (!searchValue.global) throw new TypeError("replaceAll requires a global regular expression");
        return this.replace(searchValue, replaceValue as never);
      }
      const escaped = searchValue.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return this.replace(new RegExp(escaped, "g"), replaceValue as never);
    },
  });
}

const compatibleAbortSignal = AbortSignal as typeof AbortSignal & {
  any?: (signals: AbortSignal[]) => AbortSignal;
};
if (!compatibleAbortSignal.any) {
  compatibleAbortSignal.any = (signals: AbortSignal[]) => {
    const controller = new AbortController();
    for (const signal of signals) {
      if (signal.aborted) {
        controller.abort(signal.reason);
        break;
      }
      signal.addEventListener("abort", () => controller.abort(signal.reason), { once: true });
    }
    return controller.signal;
  };
}

if (!("queueMicrotask" in globalThis)) {
  Object.defineProperty(globalThis, "queueMicrotask", {
    configurable: true,
    writable: true,
    value(callback: VoidFunction) {
      Promise.resolve()
        .then(callback)
        .catch((error) => setTimeout(() => { throw error; }, 0));
    },
  });
}

export {};
