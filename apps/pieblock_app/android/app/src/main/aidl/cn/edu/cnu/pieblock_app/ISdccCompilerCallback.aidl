package cn.edu.cnu.pieblock_app;

import android.os.Bundle;

oneway interface ISdccCompilerCallback {
    void onEvent(in Bundle event);
    void onFinished(in Bundle result);
}
